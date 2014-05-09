-module(client).
-behavior(gen_server).
%-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").
-export([start_link/1,init/1,handle_call/3,call/1,start/0,stop/0,terminate/2,handle_cast/2,handle_info/2,code_change/3]).

%% State is {master => MasterNode, alternates => Nodes, seq => SequenceNumber}

start() ->
    start_link([n1@localhost]).

%% Server teardown
terminate(Reason,_) ->
    io:fwrite("Client terminating! Reason: ~p~n", [Reason]).
stop() ->
    gen_server:cast(client, stop).

%% Unimplemented call backs
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_,_) ->
    {error,async_unsupported}.
code_change(_,_,_) ->
    {error,code_change_unsupported}.
handle_info(_,_) ->
    {error,info_unsupported}.

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
    %% Client = self(),
    ?debugFmt("calling: ~p with ~p ~p ~n",[Master,SeqNum,Operation]),
    Response = rpc:call(Master, server, clientRequest, [SeqNum,Operation], 4000),
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
	    ?debugFmt("bad response: ~p state: ~p~n",[Other,State]),
	    {reply, {unexpected_client,Other}, State}
    end.
