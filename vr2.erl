-module(vr2).
-export([startNode/4, startPrepare/4, stop/1, test/0]).
-export([master/2, replica/2, handle_event/3, init/1, terminate/3]).
-behavior(gen_fsm).

init({NodeStatus, State}) ->
    {ok, NodeStatus, State}.

startNode(NodeName, MasterNode, AllNodes, CommitFn) ->
    S = #{ commitFn => CommitFn, masterNode => MasterNode, allNodes => AllNodes, 
        clientsTable => dict:new(), viewNumber => 0, log => [], opNumber => 0, 
        commitNumber => 0 },
    if 
        NodeName == MasterNode ->
            gen_fsm:start_link({local, NodeName}, vr2, {master, S}, []);
        true ->
            gen_fsm:start_link({local, NodeName}, vr2, {replica, S}, [])
    end.

sendToClient(Client, Message) ->
    Client ! Message.

sendToReplicas(Master, Nodes, Message) ->
    lists:map(
        fun(Replica) ->
            io:fwrite("sending ~p to replica ~p~n", [Message, Replica]),
            gen_fsm:send_event(Replica, Message)
        end,
        [Node || Node <- Nodes, Node =/= Master]).


master({clientRequest, Client, RequestNum, Op}, 
    #{ clientsTable := ClientsTable, allNodes := AllNodes, masterNode := MasterNode, 
        viewNumber := ViewNumber, log := Log, opNumber := OpNumber, 
        commitNumber := CommitNumber } = State) ->
    io:fwrite("Got client request as master~n"),
    case dict:find(Client, ClientsTable) of
        {ok, {N, _}} when RequestNum < N ->
            io:fwrite("drop old request~n"),
            {next_state, master, State};
        {ok, {N, Res}} when (RequestNum == N) and (Res =/= inProgress) ->
            io:fwrite("resending old result~n"),
            sendToClient(Client, {RequestNum, Res}),
            {next_state, master, State};
        {ok, {N, Res}} when (RequestNum == N) and (Res == inProgress) ->
            io:fwrite("ignoring duplicate request, still in progress~n"),
            {next_state, master, State};
        _ ->
            io:fwrite("new request received~n"),
            NewClientsTable = dict:store(Client, {RequestNum, inProgress}, ClientsTable),
            NewLog = [Op|Log],
            NewOpNumber = OpNumber + 1,
            sendToReplicas(MasterNode, AllNodes, {prepare, ViewNumber, Op, OpNumber, CommitNumber}),
            {next_state, master, State#{ clientsTable := NewClientsTable, 
                log := NewLog, opNumber := NewOpNumber } }
    end.

replica({clientRequest, Client, _, _}, State) ->
    io:fwrite("Got client request as replica~n"),
    MasterNode = maps:get(masterNode, State),
    sendToClient(Client, {notMaster, MasterNode }),
    {next_state, replica, State};

replica({prepare, MasterViewNumber, _, _, _}, #{ viewNumber := ViewNumber} = State)
    when MasterViewNumber < ViewNumber ->
    io:fwrite("ignoring prepare from old view~n"),
    {next_state, replica, State};

replica({prepare, MasterViewNumber, Op, MasterOpNumber, MasterCommitNumber}, State) ->
    io:fwrite("got prepare request~n"),
    {next_state, replica, State}.


stop(NodeName) ->
    gen_fsm:send_all_state_event(NodeName, stop).

handle_event(stop, _, State) ->
    {stop, normal, State}.

terminate(_, _, _) ->
    io:fwrite("terminating~n").

startPrepare(NodeName, Client, RequestNum, Op) ->
    gen_fsm:send_event(NodeName, {clientRequest, Client, RequestNum, Op}).

test() ->
    Commit = fun (Client, Op, NodeType) ->
        io:fwrite("Committing as ~p : ~p~n", [NodeType, Op]),
        % or noResult
        {result, done}
    end,
    Nodes = [node1, node2],
    startNode(node1, node1, Nodes, Commit),
    startNode(node2, node1, Nodes, Commit),
    startPrepare(node1, self(), 1, hello),
    receive
        Result -> Result
    after
        200 -> timedout
    end.
