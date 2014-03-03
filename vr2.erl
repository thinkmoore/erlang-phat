-module(vr2).
-export([startNode/4, startPrepare/4, stop/0, test/0]).
-export([master/2, replica/2, handle_event/3, init/1, terminate/3]).
-behavior(gen_fsm).

init({NodeStatus, State}) ->
    {ok, NodeStatus, State}.

startNode(NodeName, MasterNode, AllNodes, CommitFn) ->
    S = #{ commitFn => CommitFn, masterNode => MasterNode, allNodes => AllNodes },
    if 
        NodeName == MasterNode ->
            gen_fsm:start_link({local, NodeName}, vr2, {master, S}, []);
        true ->
            gen_fsm:start_link({local, NodeName}, vr2, {replica, S}, [])
    end.

master({clientRequest, Client, RequestNum, Op}, State) ->
    io:fwrite("Got client request as master~n"),
    {stop, normal, State}.

replica({clientRequest, Client, _, _}, State) ->
    io:fwrite("Got client request as replica~n"),
    MasterNode = maps:get(masterNode, State),
    Client ! {notMaster, MasterNode },
    {next_state, replica, State}.

stop() ->
    gen_fsm:send_all_state_event(vr, stop).

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
    startPrepare(node2, self(), 1, hello),
    receive
        Result -> Result
    after
        200 -> timedout
    end.
