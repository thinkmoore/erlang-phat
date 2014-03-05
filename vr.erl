-module(vr).
-export([startNode/3, startPrepare/4, stop/1]).
-export([test/1]).
-export([master/2, replica/2, viewChange/2, recovery/2, handle_event/3, init/1, terminate/3]).
-export([code_change/4,handle_info/3,handle_sync_event/4]).
-behavior(gen_fsm).
%-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% INTERFACE CODE -- use startNode and startPrepare
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

startNode(NodeName = {Name,_Node}, AllNodes, CommitFn) ->
    Nodes = lists:sort(AllNodes),
    MasterNode = chooseMaster(#{ allNodes => Nodes}, 0),
    S = #{ commitFn => CommitFn, masterNode => MasterNode, allNodes => Nodes, 
        clientsTable => dict:new(), viewNumber => 0, log => [], opNumber => 0, 
        uncommittedLog => [], timeout => 4100, commitNumber => 0, viewChanges => [],
        prepareBuffer => [], masterBuffer => dict:new(), myNode => NodeName,
        doViewChanges => dict:new(), nonce => 0 },
    if 
        NodeName == MasterNode ->
            gen_fsm:start_link({local, Name}, vr, {master, S#{ timeout := 1100 }}, []);
        true ->
            gen_fsm:start_link({local, Name}, vr, {replica, S}, [])
    end.

startPrepare(NodeName, Client, RequestNum, Op) ->
    sendToMaster(NodeName, {clientRequest, Client, RequestNum, Op}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% MASTER CODE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

master(timeout, #{ allNodes := AllNodes, masterNode := MasterNode, 
    commitNumber := CommitNumber, viewNumber := ViewNumber, timeout := Timeout} = State) ->
    ?debugFmt("idle, sending commit~n", []),
    sendToReplicas(MasterNode, AllNodes, {commit, ViewNumber, CommitNumber}),
    {next_state, master, State, Timeout};

master({commit, MasterViewNumber, _}, #{ viewNumber := ViewNumber } = State)
    when MasterViewNumber > ViewNumber ->
    io:fwrite("In bad view MasterViewNumber: ~p ViewNumber ~p~n", [MasterViewNumber,ViewNumber]),
    startRecovery(State);

master({clientRequest, Client, RequestNum, Op}, 
    #{ clientsTable := ClientsTable, allNodes := AllNodes, masterNode := MasterNode, 
        viewNumber := ViewNumber, opNumber := OpNumber, 
        uncommittedLog := UncommittedLog, timeout := Timeout,
        commitNumber := CommitNumber } = State) ->
    ?debugFmt("Got client request as master~n", []),
    case dict:find(Client, ClientsTable) of
        {ok, {N, _}} when RequestNum < N ->
            ?debugFmt("drop old request~n", []),
            {next_state, master, State, Timeout};
        {ok, {N, inProgress}} when RequestNum == N ->
            ?debugFmt("ignoring duplicate request, still in progress~n", []),
            {next_state, master, State, Timeout};
        {ok, {N, Res}} when RequestNum == N ->
            ?debugFmt("resending old result~n", []),
            sendToClient(Client, {RequestNum, Res}),
            {next_state, master, State, Timeout};
        _ ->
            ?debugFmt("new request received~n", []),
            NewClientsTable = dict:store(Client, {RequestNum, inProgress}, ClientsTable),
            NewOpNumber = OpNumber + 1,
            NewLog = [{NewOpNumber, Client, RequestNum, Op}|UncommittedLog],
            sendToReplicas(MasterNode, AllNodes, 
                {prepare, ViewNumber, Op, NewOpNumber, CommitNumber, Client, RequestNum}),
            {next_state, master, State#{ clientsTable := NewClientsTable, 
                uncommittedLog := NewLog, opNumber := NewOpNumber }, Timeout }
    end;

master({prepareOk, ViewNumber, _, _}, #{ viewNumber := MasterViewNumber,
    timeout := Timeout } = State)
    when ViewNumber < MasterViewNumber ->
    ?debugFmt("ignoring prepareOk from old view", []), 
    {next_state, master, State, Timeout};

master({prepareOk, _, OpNumber, ReplicaNode} = Msg,
    #{ masterBuffer := MasterBuffer, allNodes := AllNodes, timeout := Timeout,
        uncommittedLog := UncommittedLog, commitNumber := CommitNumber } = State) ->
    ?debugFmt("received prepareok ~p~n", [Msg]),
    F = (length(AllNodes) - 1) / 2,
    MB = case dict:find(OpNumber, MasterBuffer) of
        {ok, Oks} ->
            IsMember = lists:member(ReplicaNode, Oks),
            if 
                IsMember ->
                    %?debugFmt("received dup prepareok~n", []),
                    MasterBuffer;
                true ->
                    ?debugFmt("received new prepareOk~n", []),
                    dict:store(OpNumber, [ReplicaNode|Oks], MasterBuffer)
            end;
        error ->
            ?debugFmt("received totally new prepareok~n", []),
            dict:store(OpNumber, [ReplicaNode], MasterBuffer)
    end,
    AllOks = dict:fetch(OpNumber, MB),
    if
        length(AllOks) >= F -> 
            {NLog, CTable} = doCommits(CommitNumber, OpNumber, lists:sort(UncommittedLog), State),
            {next_state, master, State#{ masterBuffer := MB, 
                commitNumber := OpNumber, uncommittedLog := NLog, clientsTable := CTable }, Timeout};
        true ->
            {next_state, master, State#{ masterBuffer := MB }, Timeout}
    end;

master({recovery, Node, Nonce}, #{ viewNumber := ViewNumber, log := Log, timeout := Timeout,
    opNumber := OpNumber, commitNumber := CommitNumber, masterNode := MasterNode} = State) ->
    ?debugFmt("got a recovery mesasge as master~n", []),
    sendToReplica(Node, 
        {recoveryResponse, ViewNumber, Nonce, Log, OpNumber, CommitNumber, MasterNode}),
    {next_state, master, State, Timeout};

master(UnknownMessage, #{ timeout := Timeout } = State) when UnknownMessage =/= fault ->
    ?debugFmt("master got unknown message: ~p~n", [UnknownMessage]),
    {next_state, master, State, Timeout}.

doCommits(_, _, [], #{ clientsTable := ClientsTable }) -> {[], ClientsTable};
doCommits(From, To, UncommittedLog, #{ log := Log, commitFn := CommitFn, 
    clientsTable := ClientsTable } = State) ->
    {[{ON, C, RN, Op} = Entry], Rest} = lists:split(1, UncommittedLog),
    if
        (ON > From) and (ON =< To) ->
            ?debugFmt("committing ~p on master~n", [ON]),
            Result = case CommitFn(C, Op, master) of
                {reply, Res} ->
                    sendToClient(C, {RN, Res}),
                    Res;
                _ ->
                    ?debugFmt("not replying to client per app request~n", []),
                    unknown
            end,
            NewClientsTable = dict:store(C, {RN, Result}, ClientsTable),
            doCommits(From, To, Rest, State#{ log := [Entry|Log], clientsTable := NewClientsTable });
        true ->
            { UncommittedLog, ClientsTable }
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% REPLICA CODE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

replica({commit, MasterViewNumber, _}, #{ viewNumber := ViewNumber} = State)
    when MasterViewNumber > ViewNumber ->
    ?debugFmt("my view is out of date, need to recover~n", []),
    startRecovery(State);

replica({commit, MasterViewNumber, _}, #{ timeout := Timeout,
    viewNumber := ViewNumber} = State)
    when MasterViewNumber < ViewNumber ->
    ?debugFmt("ignoring prepare from old view~n", []),
    {next_state, replica, State, Timeout};

replica({commit, _, MasterCommitNumber}, 
    #{ prepareBuffer := PrepareBuffer, opNumber := OpNumber } = State) ->
    ?debugFmt("got commit request~n", []),
    processPrepareOrCommit(OpNumber, MasterCommitNumber, PrepareBuffer, State);

replica({clientRequest, Client, _, _}, #{ timeout := Timeout } = State) ->
    ?debugFmt("Got client request as replica~n", []),
    MasterNode = maps:get(masterNode, State),
    sendToClient(Client, {notMaster, MasterNode }),
    {next_state, replica, State, Timeout};

replica({prepare, MasterViewNumber, _, _, _, _, _}, #{ viewNumber := ViewNumber} = State)
    when MasterViewNumber > ViewNumber ->
    ?debugFmt("my view is out of date, need to recover~n", []),
    startRecovery(State);

replica({prepare, MasterViewNumber, _, _, _, _, _}, #{ timeout := Timeout,
    viewNumber := ViewNumber} = State)
    when MasterViewNumber < ViewNumber ->
    ?debugFmt("ignoring prepare from old view~n", []),
    {next_state, replica, State, Timeout};

replica({prepare, _, Op, OpNumber, MasterCommitNumber, Client, RequestNum}, 
    #{ prepareBuffer := PrepareBuffer } = State) ->
    Message = {OpNumber, Op, Client, RequestNum},
    NewPrepareBuffer = lists:sort([Message|PrepareBuffer]),
    processPrepareOrCommit(OpNumber, MasterCommitNumber, NewPrepareBuffer, State);

replica(timeout, #{ viewNumber := ViewNumber, myNode := MyNode, allNodes := Nodes, 
    timeout := Timeout, masterNode := MasterNode } = State) ->
    NewViewNumber = ViewNumber + 1,
    NewMaster = chooseMaster(State, NewViewNumber),
    ?debugFmt("timeout -- MASTER HAS FAILED?? I think new master is now ~p - initiating view change~n", [NewMaster]),
    io:fwrite("replica ~p timed out from master, initating view change for view ~p~n", [MyNode, ViewNumber]),
    sendToReplicas(MasterNode, Nodes, {startViewChange, NewViewNumber, MyNode}),
    {next_state, viewChange, State#{ viewNumber := NewViewNumber, myNode := MyNode, 
        masterNode := NewMaster }, Timeout };

replica({startViewChange, _, _} = VC, State) ->
    handleStartViewChange(VC, State, replica);

replica({revovery, _, _}, State) ->
    ?debugFmt("got recovery message, but I am not master, ignoring~n", []),
    {next_state, replica, State};

replica(UnknownMessage, State) ->
    ?debugFmt("replica got unknown message: ~p~n", [UnknownMessage]),
    {next_state, replica, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% VIEW CHANGING CODE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

viewChange({startViewChange, _, _} = VC, State) ->
    handleStartViewChange(VC, State, viewChange);

viewChange({doViewChange, NViewNumber, NLog, NOpNumber, NCommitNumber, Node}, 
    #{ doViewChanges := DoViewChanges, masterNode := MasterNode, myNode := MyNode,
        log := MyLog, opNumber := OpNumber, commitNumber := CommitNumber,
        allNodes := AllNodes, timeout := Timeout, viewNumber := ViewNumber } = State)
    when (MasterNode == MyNode) and (ViewNumber =< NViewNumber) ->
    ?debugFmt("received doViewChange~n", []),
    F = (length(AllNodes) - 1) / 2,
    case dict:find(Node, DoViewChanges) of
        {ok, _} ->
            {next_state, viewChange, State, Timeout};
        error ->
            VCSizes = dict:size(DoViewChanges),
            if 
                (VCSizes + 1) > F ->
                    % process new master, startView
                    ?debugFmt("becoming master~n", []),
                    {MaxLog, MaxOp, MaxCommit, MaxView} = 
                        findLargestLog(DoViewChanges, {MyLog, OpNumber, CommitNumber, ViewNumber}),
                    io:fwrite("Node ~p is now becoming master for view ~p~n", [MasterNode, MaxView]),
                    if 
                        CommitNumber < MaxCommit ->
                            ?debugFmt("committing undone things~n", []),
                            throw({notyetdonesorry});
                        true ->
                            ?debugFmt("no need to commit undone things, all up to date!~n", [])
                    end,
                    sendToReplicas(MasterNode, AllNodes, {startView, MaxView, MaxLog, MaxOp, MaxCommit, MasterNode}),
                    {next_state, master, State#{ doViewChanges := dict:new(), viewChanges := [],
                        timeout := 1000,
                        log := MaxLog, opNumber := MaxOp, commitNumber := MaxCommit, viewNumber := MaxView
                     }, 1000};
                true ->
                    NewDoViewChanges = dict:store(Node, {NLog, NOpNumber, NCommitNumber, NViewNumber}, DoViewChanges),
                    {next_state, viewChange, State#{ doViewChanges := NewDoViewChanges }, Timeout}
            end
    end;

viewChange({startView, MaxView, MaxLog, MaxOp, MaxCommit, From}, 
    #{ masterNode := MasterNode, myNode := MyNode,
        commitNumber := CommitNumber,
        timeout := _Timeout, viewNumber := ViewNumber } = State)
    when  (MasterNode == From) and (ViewNumber =< MaxView) ->
    ?debugFmt("got start view~n", []),
    if 
        CommitNumber < MaxCommit ->
            ?debugFmt("committing undone things~n", []),
            throw({notyetdonesorry});
        true ->
            ?debugFmt("no need to commit undone things, all up to date!~n", [])
    end,
    ?debugFmt("returning to normal operation as replica~n", []),
    io:fwrite("Node ~p to replica for master ~p and view ~p~n", [MyNode, MasterNode, MaxView]),
    {next_state, replica, State#{ viewNumber := MaxView, opNumber := MaxOp, 
        commitNumber := CommitNumber, log := MaxLog, doViewChanges := dict:new(), 
        timeout := 4100,
        viewChanges := [] }, 4100};

viewChange(UnknownMessage, #{ timeout := Timeout} = State) ->
    ?debugFmt("view changing replica got unknown/invalid message: ~p~n", [UnknownMessage]),
    {next_state, viewChange, State, Timeout}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% RECOVERY CODE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

recovery({recoveryResponse, ViewNumber, Nonce, Log, MaxOp, MaxCommit, MasterNode},
    #{ timeout := Timeout, nonce := MyNonce, myNode := MyNode, 
    commitNumber := CommitNumber } = State)
    when MyNonce == Nonce ->
    ?debugFmt("recovering (got correct nonce)~n", []),
    if 
        CommitNumber < MaxCommit ->
            ?debugFmt("committing undone things~n", []),
            throw({notyetdonesorry});
        true ->
            ?debugFmt("no need to commit undone things, all up to date!~n", [])
    end,
    io:fwrite("replica ~p recovered to view ~p~n", [MyNode, ViewNumber]),
    {next_state, replica, State#{ viewNumber := ViewNumber, log := Log, 
        opNumber := MaxOp, commitNumber := MaxCommit, masterNode := MasterNode}, 
        Timeout};

recovery(UnknownMessage, #{ timeout := Timeout} = State) ->
    ?debugFmt("recovering replica got unknown/invalid message: ~p~n", [UnknownMessage]),
    {next_state, recovery, State, Timeout}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% HELPER FUNCTIONS (mostly for replica or view changing)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

findLargestLog(DoViewChanges, {_Log, _ON, _KN, _VN} = Init) ->
    dict:fold(fun(_, {CLog, CON, CKN, CVN}, {ALog, AON, AKN, AVN}) ->
        if
            (CVN >= AVN) and (CON >= AON) ->
                {CLog, CON, CKN, CVN};
            (CVN == AVN) and (CKN >= AKN) ->
                {ALog, AON, CKN, AVN};
            true ->
                {ALog, AON, AKN, AVN}
        end
    end, Init, DoViewChanges).

chooseMaster(#{ allNodes := AllNodes }, ViewNumber) ->
    lists:nth((ViewNumber rem length(AllNodes)) + 1, AllNodes).

%%% XXX: This is pretty inefficient, instead should keep being a replica,
%%% because one timedout replica will force an entire view change
handleStartViewChange({startViewChange, NewViewNumber, Node} = VC, 
    #{ viewNumber := ViewNumber, myNode := MyNode, 
    allNodes := Nodes } = State, OldState)
    when ViewNumber < NewViewNumber ->
    OldView = NewViewNumber - 1,
    OldMaster = chooseMaster(State, OldView),
    NewMaster = chooseMaster(State, NewViewNumber),
    ?debugFmt("Starting view change because I see a view change. ", []),
    ?debugFmt("I think new master is now ~p~n", [NewMaster]),
    
    sendToReplicas(OldMaster, Nodes, {startViewChange, NewViewNumber, MyNode}),
    
    handleStartViewChange(VC, State#{ viewNumber := NewViewNumber, 
        viewChanges := [Node], masterNode := chooseMaster(State, NewViewNumber) }, OldState);

handleStartViewChange({startViewChange, NewViewNumber, Node}, 
    #{ viewNumber := ViewNumber, myNode := MyNode, timeout := Timeout,  allNodes := AllNodes,
    commitNumber := CommitNumber, opNumber := OpNumber, log := Log,
    viewChanges := ViewChanges, masterNode := MasterNode } = State, _OldState)
    when ViewNumber == NewViewNumber ->
    ?debugFmt("processing startViewChange~n", []),
    F = (length(AllNodes) - 1) / 2,
    IsMember = lists:member(Node, ViewChanges),
    if
        IsMember -> 
            {next_state, viewChange, State, Timeout};
        (length(ViewChanges) + 1) > F ->
            sendToMaster(MasterNode, {doViewChange, ViewNumber, Log, OpNumber, CommitNumber, MyNode}),
            {next_state, viewChange, State#{ viewChanges := [Node|ViewChanges] }};
        true ->
            {next_state, viewChange, State#{ viewChanges := [Node|ViewChanges] }}
    end;

handleStartViewChange({startViewChange, NewViewNumber, _Node}, 
    #{ timeout := Timeout, viewNumber := ViewNumber } = State, OldState)
    when ViewNumber > NewViewNumber ->
    ?debugFmt("ignoring old view change~n", []),
    {next_state, OldState, State, Timeout}.

processPrepareOrCommit(OpNumber, MasterCommitNumber, NewPrepareBuffer, 
    #{ timeout := Timeout } = State) ->
    NewState = processBuffer(State#{ prepareBuffer := NewPrepareBuffer }, 
        NewPrepareBuffer, MasterCommitNumber),
    #{  masterNode := MasterNode,  viewNumber := ViewNumber,
        commitNumber := CommitNumber, myNode := MyNode } = NewState,
    if
        CommitNumber < MasterCommitNumber ->
            % todo send getstate
            ?debugFmt("missed an op, need to recover", []),
            startRecovery(State);
        true ->
            ?debugFmt("replica completed up to K=~p,O=~p~n", [CommitNumber, OpNumber]),
            sendToMaster(MasterNode, {prepareOk, ViewNumber, OpNumber, MyNode}),
            {next_state, replica, NewState, Timeout}
    end.

processBuffer(State, [], _) -> State;
processBuffer(#{ clientsTable := ClientsTable, opNumber := GlobalOpNumber, 
    commitFn := CommitFn, log := Log } = State, 
    Buffer, MasterCommitNumber) ->
    {[{OpNumber, Op, Client, RequestNum}], Rest} = lists:split(1, Buffer),
    ?debugFmt("processing ~p~n", [OpNumber]),
    if
        OpNumber + 1 < GlobalOpNumber ->
            ?debugFmt("Gap, don't process~n", []),
            State;
        OpNumber =< MasterCommitNumber ->
            ?debugFmt("committing ~p on replica~n", [OpNumber]),
            CommitFn(Client, Op, replica),
            processBuffer(State#{ commitNumber :=  OpNumber, 
                prepareBuffer := Rest }, 
                Rest, MasterCommitNumber);
        OpNumber == GlobalOpNumber + 1 ->
            ?debugFmt("adding ~p to replica log~n", [OpNumber]),
            NewClientsTable = dict:store(Client, {RequestNum, inProgress}, ClientsTable),
            NewLog = [{OpNumber, Client, RequestNum, Op}|Log],
            processBuffer(State#{ log := NewLog, opNumber := OpNumber, 
                clientsTable := NewClientsTable }, Rest, MasterCommitNumber);
        true ->
            processBuffer(State, Rest, MasterCommitNumber)
    end.

startRecovery(#{myNode := MyNode, allNodes := AllNodes, timeout := Timeout} = State) ->
    ?debugFmt("node ~p starting recovery~n", [MyNode]),
    Nonce = now(),
    sendToReplicas(MyNode, AllNodes, {recovery, MyNode, Nonce}),
    {next_state, recovery, State#{nonce := Nonce}, Timeout}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Utility functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init({NodeStatus, #{ timeout := Timeout, masterNode := MasterNode, myNode := MyNode } = State}) ->
    io:fwrite("VR Node ~p starting with master node ~p~n", [MyNode, MasterNode]),
    {ok, NodeStatus, State, Timeout}.

sendToClient(Client, Message) ->
    ?debugFmt("Sending to client ~p: ~p~n", [Client,Message]),
    Client ! Message.

sendToMaster(Master, Message) ->
    ?debugFmt("Sending ~p to ~p~n", [Message,Master]),
    gen_fsm:send_event(Master, Message).

sendToReplicas(Master, Nodes, Message) ->
    lists:map(
        fun(Replica) ->
            sendToReplica(Replica, Message)
        end,
        [Node || Node <- Nodes, Node =/= Master]).

sendToReplica(Replica, Message) ->
    ?debugFmt("sending ~p to replica ~p~n", [Message, Replica]),
    gen_fsm:send_event(Replica, Message).

stop(NodeName) ->
    gen_fsm:send_all_state_event(NodeName, stop).

handle_event(stop, _, State) ->
    {stop, normal, State}.

terminate(_, _, #{ myNode := MyNode, masterNode := MasterNode }) ->
    io:fwrite("VR node ~p shutting down (master was ~p)~n", [MyNode, MasterNode]),
    ok.

%% UNIMPLEMENTED
%% Unimplemented call backs
code_change(_,_,_,_) ->
    {error,code_change_unsupported}.
handle_info(_,_,_) ->
    {error, info_unsupported}.
handle_sync_event(_,_,_,_) ->
    {error, info_unsupported}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% TEST CODE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

testReceiveResult() ->
    receive
        Result -> io:fwrite("~p~n", [Result])
    after
        200 -> io:fwrite("timed out~n")
    end.

testPrintCommit(Client, Op, NodeType) ->
    io:fwrite("Committing ~p for ~p as ~p~n", [Op, Client, NodeType]),
    % or doNotReply
    {reply, {done, Op}}.

testOldValue(Node1 = {_,N1},Node2 = {_,N2}) ->
    Commit = fun testPrintCommit/3,
    Nodes = [Node1,Node2],
    rpc:call(N1, vr, startNode, [Node1, Nodes, Commit]),
    rpc:call(N2, vr, startNode, [Node2, Nodes, Commit]),
    startPrepare(Node1, self(), 1, hello),
    testReceiveResult(),
    startPrepare(Node1, self(), 1, hello),
    testReceiveResult(),
    rpc:call(N1, vr, stop, [Node1]),
    rpc:call(N2, vr, stop, [Node2]).

testTwoCommits(Node1 = {_,N1},Node2 = {_,N2}) ->
    Commit = fun testPrintCommit/3,
    Nodes = [Node1,Node2],
    rpc:call(N1, vr, startNode, [Node1, Nodes, Commit]),
    rpc:call(N2, vr, startNode, [Node2, Nodes, Commit]),
    startPrepare(Node1, self(), 1, hello1),
    testReceiveResult(),
    startPrepare(Node1, self(), 2, hello2),
    testReceiveResult(),
    rpc:call(N1, vr, stop, [Node1]),
    rpc:call(N2, vr, stop, [Node2]).

testMasterFailover(Node1 = {_,N1}, Node2 = {_,N2}, Node3 = {_, N3},
    Node4 = {_, N4},Node5 = {_, N5}) ->
    Commit = fun testPrintCommit/3,
    Nodes = [Node1, Node2, Node3, Node4, Node5],
    rpc:call(N1, vr, startNode, [Node1, Nodes, Commit]),
    rpc:call(N2, vr, startNode, [Node2, Nodes, Commit]),
    rpc:call(N3, vr, startNode, [Node3, Nodes, Commit]),
    rpc:call(N4, vr, startNode, [Node4, Nodes, Commit]),
    rpc:call(N5, vr, startNode, [Node5, Nodes, Commit]),
    startPrepare(Node1, self(), 1, hello1),
    testReceiveResult(),
    rpc:call(N1, vr, stop, [Node1]),
    io:fwrite("now killed master, waiting 6 seconds...~n"),
    waitBetweenTests(6000),
    io:fwrite("sending next operation"),
    startPrepare(Node2, self(), 2, hello2),
    testReceiveResult(),
    rpc:call(N2, vr, stop, [Node2]),
    rpc:call(N3, vr, stop, [Node3]),
    rpc:call(N4, vr, stop, [Node4]),
    rpc:call(N5, vr, stop, [Node5]),
    io:fwrite("done").

testRecovery(Node1 = {_,N1}, Node2 = {_,N2}, Node3 = {_, N3}) ->
    io:fwrite("only starting nodes 1 and 2~n"),
    Commit = fun testPrintCommit/3,
    Nodes = [Node1, Node2, Node3],
    rpc:call(N1, vr, startNode, [Node1, Nodes, Commit]),
    rpc:call(N2, vr, startNode, [Node2, Nodes, Commit]),
    startPrepare(Node1, self(), 1, hello1),
    testReceiveResult(),
    io:fwrite("bringing up node 3 now~n"),
    rpc:call(N3, vr, startNode, [Node3, Nodes, Commit]),
    startPrepare(Node1, self(), 2, hello2),
    testReceiveResult(),
    rpc:call(N1, vr, stop, [Node1]),
    rpc:call(N2, vr, stop, [Node2]),
    rpc:call(N3, vr, stop, [Node3]),
    io:fwrite("done").

waitBetweenTests(Time) ->
    receive
    after
        Time -> ok
    end.

test(local) ->
    Node1 = {vr1,node()},
    Node2 = {vr2,node()},
    Node3 = {vr3,node()},
    Node4 = {vr4,node()},
    Node5 = {vr5,node()},
    runTest(Node1, Node2, Node3, Node4, Node5);

test({remote, Node1, Node2, Node3, Node4, Node5}) ->
    runTest({vr, Node1}, {vr, Node2}, {vr, Node3}, {vr, Node4}, {vr, Node5}).

runTest(Node1, Node2, Node3, Node4, Node5) ->
    % io:fwrite("~n~n--- Testing old value send...~n"),
    % testOldValue(Node1, Node2),
    % waitBetweenTests(100),
    % io:fwrite("~n~n--- Testing two commits...~n"),
    % testTwoCommits(Node1, Node2),
    % waitBetweenTests(100),
    %io:fwrite("~n~n--- Testing master failover...~n"),
    %testMasterFailover(Node1, Node2, Node3, Node4, Node5),
    %waitBetweenTests(100),
    io:fwrite("~n~n--- Testing recovery...~n"),
    testRecovery(Node1, Node2, Node3),
    waitBetweenTests(100),
    io:fwrite("~n~n--- Tests complete ~n").
