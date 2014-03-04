-module(vr).
-export([startNode/4, startPrepare/4, stop/1]).
-export([test/1]).
-export([master/2, replica/2, handle_event/3, init/1, terminate/3]).
-behavior(gen_fsm).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% INTERFACE CODE -- use startNode and startPrepare
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

startNode(NodeName = {Name,_Node}, MasterNode, AllNodes, CommitFn) ->
    S = #{ commitFn => CommitFn, masterNode => MasterNode, allNodes => AllNodes, 
        clientsTable => dict:new(), viewNumber => 0, log => [], opNumber => 0, 
        uncommittedLog => [], timeout => 4000, commitNumber => 0, 
        prepareBuffer => [], masterBuffer => dict:new(), myNode => NodeName },
    if 
        NodeName == MasterNode ->
            gen_fsm:start_link({local, Name}, vr, {master, S#{ timeout := 1000 }}, []);
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
    io:fwrite("idle, sending commit~n"),
    sendToReplicas(MasterNode, AllNodes, {commit, ViewNumber, CommitNumber}),
    {next_state, master, State, Timeout};

master({clientRequest, Client, RequestNum, Op}, 
    #{ clientsTable := ClientsTable, allNodes := AllNodes, masterNode := MasterNode, 
        viewNumber := ViewNumber, opNumber := OpNumber, 
        uncommittedLog := UncommittedLog, timeout := Timeout,
        commitNumber := CommitNumber } = State) ->
    io:fwrite("Got client request as master~n"),
    case dict:find(Client, ClientsTable) of
        {ok, {N, _}} when RequestNum < N ->
            io:fwrite("drop old request~n"),
            {next_state, master, State, Timeout};
        {ok, {N, inProgress}} when RequestNum == N ->
            io:fwrite("ignoring duplicate request, still in progress~n"),
            {next_state, master, State, Timeout};
        {ok, {N, Res}} when RequestNum == N ->
            io:fwrite("resending old result~n"),
            sendToClient(Client, {RequestNum, Res}),
            {next_state, master, State, Timeout};
        _ ->
            io:fwrite("new request received~n"),
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
    io:fwrite("ignoring prepareOk from old view"), 
    {next_state, master, State, Timeout};

master({prepareOk, _, OpNumber, ReplicaNode} = Msg, 
    #{ masterBuffer := MasterBuffer, allNodes := AllNodes, timeout := Timeout,
        uncommittedLog := UncommittedLog, commitNumber := CommitNumber } = State) ->
    io:fwrite("received prepareok ~p~n", [Msg]),
    F = (length(AllNodes) - 1) / 2,
    MB = case dict:find(OpNumber, MasterBuffer) of
        {ok, Oks} ->
            IsMember = lists:member(ReplicaNode, Oks),
            if 
                IsMember ->
                    io:fwrite("received dup prepareok~n"),
                    MasterBuffer;
                true ->
                    io:fwrite("received new prepareOk~n"),
                    dict:store(OpNumber, [ReplicaNode|Oks], MasterBuffer)
            end;
        error ->
            io:fwrite("received totally new prepareok~n"),
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
    end.

doCommits(_, _, [], #{ clientsTable := ClientsTable }) -> {[], ClientsTable};
doCommits(From, To, UncommittedLog, #{ log := Log, commitFn := CommitFn, 
    clientsTable := ClientsTable } = State) ->
    {[{ON, C, RN, Op} = Entry], Rest} = lists:split(1, UncommittedLog),
    if
        (ON > From) and (ON =< To) ->
            io:fwrite("committing ~p on master~n", [ON]),
            Result = case CommitFn(C, Op, master) of
                {reply, Res} ->
                    sendToClient(C, {RN, Res}),
                    Res;
                _ ->
                    io:fwrite("not replying to client per app request~n"),
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

replica({commit, MasterViewNumber, _}, #{ timeout := Timeout, 
    viewNumber := ViewNumber} = State)
    when MasterViewNumber > ViewNumber ->
    io:fwrite("my view is out of date, need state transfer~n"),
    {next_state, stateTransfer, State, Timeout};

replica({commit, MasterViewNumber, _}, #{ timeout := Timeout,
    viewNumber := ViewNumber} = State)
    when MasterViewNumber < ViewNumber ->
    io:fwrite("ignoring prepare from old view~n"),
    {next_state, replica, State, Timeout};

replica({commit, _, MasterCommitNumber}, 
    #{ prepareBuffer := PrepareBuffer, opNumber := OpNumber } = State) ->
    io:fwrite("got commit request~n"),
    processPrepareOrCommit(OpNumber, MasterCommitNumber, PrepareBuffer, State);

replica({clientRequest, Client, _, _}, #{ timeout := Timeout } = State) ->
    io:fwrite("Got client request as replica~n"),
    MasterNode = maps:get(masterNode, State),
    sendToClient(Client, {notMaster, MasterNode }),
    {next_state, replica, State, Timeout};

replica({prepare, MasterViewNumber, _, _, _, _, _}, #{ timeout := Timeout, 
    viewNumber := ViewNumber} = State)
    when MasterViewNumber > ViewNumber ->
    io:fwrite("my view is out of date, need state transfer~n"),
    {next_state, stateTransfer, State, Timeout};

replica({prepare, MasterViewNumber, _, _, _, _, _}, #{ timeout := Timeout,
    viewNumber := ViewNumber} = State)
    when MasterViewNumber < ViewNumber ->
    io:fwrite("ignoring prepare from old view~n"),
    {next_state, replica, State, Timeout};

replica({prepare, _, Op, OpNumber, MasterCommitNumber, Client, RequestNum}, 
    #{ prepareBuffer := PrepareBuffer } = State) ->
    io:fwrite("got prepare request~n"),
    Message = {OpNumber, Op, Client, RequestNum},
    NewPrepareBuffer = lists:sort([Message|PrepareBuffer]),
    processPrepareOrCommit(OpNumber, MasterCommitNumber, NewPrepareBuffer, State).

processPrepareOrCommit(OpNumber, MasterCommitNumber, NewPrepareBuffer, 
    #{ timeout := Timeout } = State) ->
    NewState = processBuffer(State#{ prepareBuffer := NewPrepareBuffer }, 
        NewPrepareBuffer, MasterCommitNumber),
    #{  masterNode := MasterNode,  viewNumber := ViewNumber,
        commitNumber := CommitNumber, myNode := MyNode } = NewState,
    if
        CommitNumber < MasterCommitNumber ->
            % todo send getstate
            io:fwrite("missed an op, need state transfer"),
            {next_state, stateTransfer, NewState, Timeout};
        true ->
            io:fwrite("replica completed up to K=~p,O=~p~n", [CommitNumber, OpNumber]),
            sendToMaster(MasterNode, {prepareOk, ViewNumber, OpNumber, MyNode}),
            {next_state, replica, NewState, Timeout}
    end.

processBuffer(State, [], _) -> State;
processBuffer(#{ clientsTable := ClientsTable, opNumber := GlobalOpNumber, 
    commitFn := CommitFn, log := Log } = State, 
    Buffer, MasterCommitNumber) ->
    {[{OpNumber, Op, Client, RequestNum}], Rest} = lists:split(1, Buffer),
    io:fwrite("processing ~p~n", [OpNumber]),
    if
        OpNumber + 1 < GlobalOpNumber ->
            io:fwrite("Gap, don't process~n"),
            State;
        OpNumber =< MasterCommitNumber ->
            io:fwrite("committing ~p on replica~n", [OpNumber]),
            CommitFn(Client, Op, replica),
            processBuffer(State#{ commitNumber :=  OpNumber, 
                prepareBuffer := Rest }, 
                Rest, MasterCommitNumber);
        OpNumber == GlobalOpNumber + 1 ->
            io:fwrite("adding ~p to replica log~n", [OpNumber]),
            NewClientsTable = dict:store(Client, {RequestNum, inProgress}, ClientsTable),
            NewLog = [{OpNumber, Client, RequestNum, Op}|Log],
            processBuffer(State#{ log := NewLog, opNumber := OpNumber, 
                clientsTable := NewClientsTable }, Rest, MasterCommitNumber);
        true ->
            processBuffer(State, Rest, MasterCommitNumber)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Utility functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

init({NodeStatus, #{ timeout := Timeout } = State}) ->
    {ok, NodeStatus, State, Timeout}.

sendToClient(Client, Message) ->
    io:fwrite("Sending to client ~p: ~p~n", [Client,Message]),
    Client ! Message.

sendToMaster(Master, Message) ->
    io:fwrite("Sending ~p to ~p~n", [Message,Master]),
    gen_fsm:send_event(Master, Message).

sendToReplicas(Master, Nodes, Message) ->
    lists:map(
        fun(Replica) ->
            io:fwrite("sending ~p to replica ~p~n", [Message, Replica]),
            gen_fsm:send_event(Replica, Message)
        end,
        [Node || Node <- Nodes, Node =/= Master]).

stop(NodeName) ->
    gen_fsm:send_all_state_event(NodeName, stop).

handle_event(stop, _, State) ->
    {stop, normal, State}.

terminate(_, _, _) ->
    ok.

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
    rpc:call(N1, vr, startNode, [Node1, Node1, Nodes, Commit]),
    rpc:call(N2, vr, startNode, [Node2, Node1, Nodes, Commit]),
    startPrepare(Node1, self(), 1, hello),
    testReceiveResult(),
    startPrepare(Node1, self(), 1, hello),
    testReceiveResult(),
    rpc:call(N1, vr, stop, [Node1]),
    rpc:call(N2, vr, stop, [Node2]).

testTwoCommits(Node1 = {_,N1},Node2 = {_,N2}) ->
    Commit = fun testPrintCommit/3,
    Nodes = [Node1,Node2],
    rpc:call(N1, vr, startNode, [Node1, Node1, Nodes, Commit]),
    rpc:call(N2, vr, startNode, [Node2, Node1, Nodes, Commit]),
    startPrepare(Node1, self(), 1, hello1),
    testReceiveResult(),
    startPrepare(Node1, self(), 2, hello2),
    testReceiveResult(),
    rpc:call(N1, vr, stop, [Node1]),
    rpc:call(N2, vr, stop, [Node2]).

testMasterFailover(Node1 = {_,N1}, Node2 = {_,N2}, Node3 = {_, N3}) ->
    Commit = fun testPrintCommit/3,
    Nodes = [Node1, Node2, Node3],
    rpc:call(N1, vr, startNode, [Node1, Node1, Nodes, Commit]),
    rpc:call(N2, vr, startNode, [Node2, Node1, Nodes, Commit]),
    rpc:call(N3, vr, startNode, [Node3, Node1, Nodes, Commit]),
    io:fwrite("waiting 5 seconds...~n"),
    waitBetweenTests(5000),
    rpc:call(N1, vr, stop, [Node1]),
    rpc:call(N2, vr, stop, [Node2]),
    rpc:call(N3, vr, stop, [Node3]).
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
    runTest(Node1, Node2, Node3);

test({remote, Node1, Node2, Node3}) ->
    runTest({vr, Node1}, {vr, Node2}, {vr, Node3}).

runTest(Node1, Node2, Node3) ->
    io:fwrite("~n~n--- Testing old value send...~n"),
    testOldValue(Node1, Node2),
    waitBetweenTests(100),
    io:fwrite("~n~n--- Testing two commits...~n"),
    testTwoCommits(Node1, Node2),
    waitBetweenTests(100),
    io:fwrite("~n~n--- Testing master failover...~n"),
    testMasterFailover(Node1, Node2, Node3),
    waitBetweenTests(100),
    io:fwrite("~n~n--- Tests complete ~n").
