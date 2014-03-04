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
        uncommittedLog => [],
        commitNumber => 0, prepareBuffer => [], masterBuffer => dict:new(), myNode => NodeName },
    if 
        NodeName == MasterNode ->
            gen_fsm:start_link({local, Name}, vr, {master, S}, []);
        true ->
            gen_fsm:start_link({local, Name}, vr, {replica, S}, [])
    end.

startPrepare(NodeName, Client, RequestNum, Op) ->
    sendToMaster(NodeName, {clientRequest, Client, RequestNum, Op}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% MASTER CODE
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

master({clientRequest, Client, RequestNum, Op}, 
    #{ clientsTable := ClientsTable, allNodes := AllNodes, masterNode := MasterNode, 
        viewNumber := ViewNumber, opNumber := OpNumber, 
        uncommittedLog := UncommittedLog,
        commitNumber := CommitNumber } = State) ->
    io:fwrite("Got client request as master~n"),
    case dict:find(Client, ClientsTable) of
        {ok, {N, _}} when RequestNum < N ->
            io:fwrite("drop old request~n"),
            {next_state, master, State};
        {ok, {N, inProgress}} when RequestNum == N ->
            io:fwrite("ignoring duplicate request, still in progress~n"),
            {next_state, master, State};
        {ok, {N, Res}} when RequestNum == N ->
            io:fwrite("resending old result~n"),
            sendToClient(Client, {RequestNum, Res}),
            {next_state, master, State};
        _ ->
            io:fwrite("new request received~n"),
            NewClientsTable = dict:store(Client, {RequestNum, inProgress}, ClientsTable),
            NewOpNumber = OpNumber + 1,
            NewLog = [{NewOpNumber, Client, RequestNum, Op}|UncommittedLog],
            sendToReplicas(MasterNode, AllNodes, 
                {prepare, ViewNumber, Op, NewOpNumber, CommitNumber, Client, RequestNum}),
            {next_state, master, State#{ clientsTable := NewClientsTable, 
                uncommittedLog := NewLog, opNumber := NewOpNumber } }
    end;

master({prepareOk, ViewNumber, _, _}, #{ viewNumber := MasterViewNumber })
    when ViewNumber < MasterViewNumber ->
    io:fwrite("ignoring prepareOk from old view"); 

master({prepareOk, _, OpNumber, ReplicaNode} = Msg, 
    #{ masterBuffer := MasterBuffer, allNodes := AllNodes, 
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
                commitNumber := OpNumber, uncommittedLog := NLog, clientsTable := CTable }};
        true ->
            {next_state, master, State#{ masterBuffer := MB }}
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

replica({clientRequest, Client, _, _}, State) ->
    io:fwrite("Got client request as replica~n"),
    MasterNode = maps:get(masterNode, State),
    sendToClient(Client, {notMaster, MasterNode }),
    {next_state, replica, State};

replica({prepare, MasterViewNumber, _, _, _, _, _}, #{ viewNumber := ViewNumber} = State)
    when MasterViewNumber > ViewNumber ->
    io:fwrite("my view is out of date, need state transfer~n"),
    {next_state, stateTransfer, State};

replica({prepare, MasterViewNumber, _, _, _, _, _}, #{ viewNumber := ViewNumber} = State)
    when MasterViewNumber < ViewNumber ->
    io:fwrite("ignoring prepare from old view~n"),
    {next_state, replica, State};

replica({prepare, _, Op, OpNumber, MasterCommitNumber, Client, RequestNum}, 
    #{ prepareBuffer := PrepareBuffer } = State) ->
    io:fwrite("got prepare request~n"),
    Message = {OpNumber, Op, Client, RequestNum},
    NewPrepareBuffer = lists:sort([Message|PrepareBuffer]),
    NewState = processBuffer(State#{ prepareBuffer := NewPrepareBuffer }, 
        NewPrepareBuffer, MasterCommitNumber),
    #{  masterNode := MasterNode,  viewNumber := ViewNumber,
        commitNumber := CommitNumber, myNode := MyNode } = NewState,
    if
        CommitNumber < MasterCommitNumber ->
            % todo send getstate
            io:fwrite("missed an op, need state transfer"),
            {next_state, stateTransfer, NewState};
        true ->
            io:fwrite("replica completed up to K=~p,O=~p~n", [CommitNumber, OpNumber]),
            sendToMaster(MasterNode, {prepareOk, ViewNumber, OpNumber, MyNode}),
            {next_state, replica, NewState}
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

init({NodeStatus, State}) ->
    {ok, NodeStatus, State}.

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

waitBetweenTests() ->
    receive
    after
        100 -> ok
    end.

test(local) ->
    Node1 = {vr1,node()},
    Node2 = {vr2,node()},
    runTest(Node1,Node2);
test({remote,Node1,Node2}) ->
    runTest({vr,Node1},{vr,Node2}).

runTest(Node1,Node2) ->
    io:fwrite("~n~n--- Testing old value send...~n"),
    testOldValue(Node1,Node2),
    waitBetweenTests(),
    io:fwrite("~n~n--- Testing two commits...~n"),
    testTwoCommits(Node1,Node2),
    io:fwrite("~n~n--- Tests complete ~n").
