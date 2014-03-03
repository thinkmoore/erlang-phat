-module(vr).
-export([startMasterNode/2, startReplicaNode/3, test/0, init/1, masterAwaitingRequest/2, replicaAwaitingPrepare/2, terminate/3, stop/0, handle_event/3]).
-behavior(gen_fsm).

init({State, Master, ReplicaCommitFn}) ->
    {ok, State, {[], Master, dict:new(), 0, 0, 0, ReplicaCommitFn}}.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% REPLICA %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

replicaAwaitingPrepare({prepare, MasterViewNumber, Op, MasterOpNumber, MasterCommitNumber}, 
    State = {Log, Master, ClientsTable, OpNumber, CommitNumber, ViewNumber, ReplicaCommitFn}) ->
    io:fwrite("got prepare~n"),
    if 
        (MasterCommitNumber == CommitNumber) and (MasterOpNumber == OpNumber + 1)  ->
            io:fwrite("good prepare ~n"),
            NewOpNumber = MasterOpNumber,
            NewCommitNumber = CommitNumber;
        (MasterCommitNumber > CommitNumber) and (MasterCommitNumber > OpNumber) ->
            io:fwrite("initiate state transfer~n"),
            NewOpNumber = OpNumber,
            NewCommitNumber = CommitNumber;
        (MasterCommitNumber > CommitNumber) and (MasterCommitNumber == OpNumber) ->
            io:fwrite("Ops ~s to ~s got committed ~n", [CommitNumber, MasterCommitNumber]),
            % commit them
            NewOpNumber = MasterOpNumber,
            NewCommitNumber = MasterCommitNumber;
        true ->
            io:fwrite("invariant failure: ~s~n", {OpNumber, CommitNumber, MasterOpNumber, MasterCommitNumber}),
            erlang:error(badReplicaPrepareInvariant)
    end,
    sendToMaster(Master, {prepareOk, Op}),
    {stop, normal, State}.


%replicaAwaitingPrepare({prepare, MasterViewNumber, Op, MasterOpNumber, MasterCommitNumber}, 
%    State = {Log, Master, ClientsTable, OpNumber, CommitNumber, ViewNumber}) ->
    


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% MASTER %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


broadcastToReplicas(Master, Message) ->
    lists:map(
        fun(Replica) ->
            io:fwrite("sending to replica ~p~n", [Replica]),
            gen_fsm:send_event(Replica,Message)
        end,
        [Node || Node <- all_nodes(), Node =/= Master]).

sendToMaster(Master,Message) ->
    io:fwrite("sending to master ~p~n", [Master]),
    gen_fsm:send_event(Master,Message).

masterAwaitingRequest({request, Op, Client, RequestNum}, 
    State = {Log, Master, ClientsTable, OpNumber, CommitNumber, ViewNumber, ReplicaCommitFn}) ->
    io:fwrite("in master awaiting request~n"),
    case dict:find(Client, ClientsTable) of
        {ok, N} when RequestNum < N -> 
            io:fwrite("drop old request~n"), {next_state, masterAwaitingRequest, State};
        {ok, {N, unknown}} when RequestNum == N -> 
            io:fwrite("drop-still working on it~n"), {next_state, masterAwaitingRequest, State};
        {ok, {N, LastValue}} when RequestNum == N -> 
            % resend(), XXX FIXME TODO
            {next_state, masterAwaitingRequest, State};
        _ -> 
            io:fwrite("new request ~p by ~p~n", [RequestNum, Client]),
            NewClientsTable = dict:store(Client, {RequestNum, unknown}, ClientsTable),
            NewLog = [Op|Log],
            NewOpNumber = OpNumber + 1,
            broadcastToReplicas(Master, {prepare, ViewNumber, Op, NewOpNumber, CommitNumber}),
            {next_state, masterAwaitingPrepareOks, {NewLog, Master, NewClientsTable, NewOpNumber, CommitNumber, ViewNumber, ReplicaCommitFn}}
    end.

stop() ->
    gen_fsm:send_all_state_event(vr, stop).

handle_event(stop, _, State) ->
    {stop, normal, State}.

terminate(_,_,_) ->
    io:fwrite("terminating!~n").

all_nodes() ->
    [vrMaster, replica1].

startMasterNode(FsmRef, CommitAsReplicaFun) ->
    gen_fsm:start_link({local, FsmRef}, vr, {masterAwaitingRequest, FsmRef, CommitAsReplicaFun}, []).

startReplicaNode(FsmRef, Master, CommitAsReplicaFun) ->
    gen_fsm:start_link({local, FsmRef}, vr, {replicaAwaitingPrepare, Master, CommitAsReplicaFun}, []).

handleClientRequest(FsmRef, Message = {Op, Client, RequestNum}) ->
    gen_fsm:send_event(FsmRef, {request, Op, Client, RequestNum}).

commitAsReplicaTest(Msg) ->
    io:fwrite("committing as replica ~p~n", [Msg]).

test() -> 
    Master = vrMaster,
    startMasterNode(Master, fun commitAsReplicaTest/1),
    startReplicaNode(replica1, Master, fun commitAsReplicaTest/1),
    handleClientRequest(Master, {hello, testClient, 1}).



