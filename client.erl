-module(client).
-behavior(gen_server).
%%-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").
-export([start_link/1,init/1,handle_call/3,call/1]).

%% State is {master => MasterNode, seq => SequenceNumber}

start_link(Master) ->
    gen_server:start_link({local,client},client,[Master],[]).

init(Master) ->
    {ok, #{master => Master, seq => 0}}.

call(Operation) ->
    gen_server:call(client,Operation).

handle_call(Operation,Caller,State) ->
    #{seq := SeqNum, master := Master} = State,
    Response = rpc:call(Master, server, clientRequest, [SeqNum,Operation], 1000),
    case Response of
	{badrpc,timeout} ->
	    ?debugMsg("Timeout, trying again~n"),
	    handle_call(Operation, Caller, State);
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
	{notMaster, MasterNode} -> 
	    ?debugFmt("Master is actually: ~p, trying again.~n",[MasterNode]),
	    NewState = State#{master := MasterNode},
	    handle_call(Operation, Caller, NewState);
	Other -> 
	    {reply, {unexpected,Other}, State}
    end.
