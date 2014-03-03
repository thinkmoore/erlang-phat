-module(vr).
-export([start/1, init/1, masterAwaitingRequest/2, terminate/3, stop/0, handle_event/3]).
-behavior(gen_fsm).

init([Master]) when Master == node() ->
    {ok, masterAwaitingRequest, {[], Master, dict:new(), 0, 0, 0}};
init([Master]) ->
    io:fwrite("i am ~s", [Master]),
    {ok, replicaAwaitingPrepare, {[], Master, dict:new(), 0, 0, 0}}.


broadcastToReplicas(Master,Message) ->
    lists:map(
      fun(Replica) ->
            io:fwrite("hello"),
              gen_fsm:send_event(Replica,Message)
      end,
      [Node || Node <- nodes(), Node =/= Master]).

masterAwaitingRequest({request, Op, Client, RequestNum}, State = {Log, Master, ClientsTable, OpNumber, CommitNumber, ViewNumber}) ->
    io:fwrite("in master awaiting request\n"),
    case dict:find(Client, ClientsTable) of
        {ok, N} when RequestNum < N -> 
            io:fwrite("drop\n"), {next_state, masterAwaitingRequest, State};
        {ok, {N, unknown}} when RequestNum == N -> 
            io:fwrite("drop-still working on it\n"), {next_state, masterAwaitingRequest, State};
        {ok, {N, LastValue}} when RequestNum == N -> 
            % resend(),
            {next_state, masterAwaitingRequest, State};
        _ -> 
            io:fwrite("new request ~p by ~p", [RequestNum, Client]),
            NewClientsTable = dict:store(Client, {RequestNum, unknown}, ClientsTable),
            NewLog = [Op|Log],
            NewOpNumber = OpNumber + 1,
            broadcastToReplicas(Master, {prepare, ViewNumber, Op, NewOpNumber, CommitNumber}),
            {next_state, masterAwaitingPrepareOks, {NewLog, Master, NewClientsTable, NewOpNumber, CommitNumber, ViewNumber}}
    end.

stop() ->
    gen_fsm:send_all_state_event(vr, stop).

handle_event(stop, _, State) ->
    {stop, normal, State}.

terminate(_,_,_) ->
    io:fwrite("terminating!\n").

start(Master) -> gen_fsm:start_link({local, vr}, vr, [Master], []),
    gen_fsm:send_event(vr, {request, hello, 1, 1}).



