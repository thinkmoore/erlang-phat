-module(client).
-behavior(gen_server).
%-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").
-export([start_link/1,init/1,handle_call/3,call/1,start/0]).

%% State is {master => MasterNode, alternates => Nodes, seq => SequenceNumber}

start() ->
    start_link([n1@localhost]).

start_link(Nodes) ->
    gen_server:start_link({local,client},client,Nodes,[]).

init([Master|Rest]) ->
    {ok, #{master => Master, alternates => [Master|Rest], seq => 0}}.

call(Operation) ->
    gen_server:call(client,Operation).

nextMaster(Master,[Master,Next|_],_) ->
    Next;
nextMaster(Master,[_|Rest],Alternates) ->
    nextMaster(Master,Rest,Alternates);
nextMaster(Master,[],Alternates) ->
    nextMaster(Master,Alternates,Alternates).

handle_call(Operation,Caller,State) ->
    #{seq := SeqNum, master := Master, alternates := Alternates} = State,
    Client = self(),
    Response = rpc:block_call(Master, server, clientRequest, [SeqNum,Operation], 4000),
    case Response of
        timeout ->
	    NewMaster = nextMaster(Master,Alternates,Alternates),
	    ?debugFmt("Timeout, trying again with next alternate ~p~n", [NewMaster]),
	    handle_call(Operation, Caller, State#{master := NewMaster});
	{Number,{ok,Result}} -> 
	    if 
		Number < SeqNum ->
		    ?debugMsg("Ignoring old response~n"), 
		    handle_call(Operation, Caller, State);
		true -> 
		    NewState = State#{seq := SeqNum + 1},
		    {reply, Result, NewState}
	    end;
	{Number,{error,Cause}} -> 
	    if 
		Number < SeqNum -> 
		    ?debugMsg("Ignoring old response~n"), 
		    handle_call(Operation, Caller, State);
		true -> 
		    NewState = State#{seq := SeqNum + 1},
		    {reply, {error,Cause}, NewState}
	    end;
	{notMaster, {_,MasterNode}} -> 
	    ?debugFmt("Master is actually: ~p, trying again.~n",[MasterNode]),
	    NewState = State#{master := MasterNode},
	    handle_call(Operation, Caller, NewState);
	Other -> 
	    {reply, {unexpected,Other}, State}
    end.
