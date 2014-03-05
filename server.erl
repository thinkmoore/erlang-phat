-module(server).
-behavior(gen_server).

-export([init/1,handle_cast/2,terminate/2]).
-export([handle_call/3,handle_info/2,code_change/3]).
-export([start_link/0,clientRequest/2,stop/0,commit/3]).

init(_) ->
    io:fwrite("Starting server on ~p~n", [node()]),
    {ok, []}.

commit(_, Op, NodeType) ->
    Ret = gen_server:call(fs,Op),
    io:fwrite("Commited ~p as ~p on ~p~n", [Ret,NodeType,node()]),
    {reply, Ret}.

handle_cast({clientRequest,From,Seq,Operation},State) ->
    vr:startPrepare({vr,node()},From,Seq,Operation),
    {noreply,State};
handle_cast(stop, State) ->
    {stop, normal, State}.

handle_call(_,_,_) ->
    {error,call_unsupported}.

handle_info(_,_) ->
    {error,info_unsupported}.

terminate(Reason, _) ->
    io:fwrite("Phat server terminating!~n~p~n", [Reason]),
    fs:stop().

code_change(_,_,_) ->
    {error, code_change_unsupported}.

start_link() ->
    gen_server:start_link({local, ps}, server, [], []).

stop() ->
    gen_server:cast(stop).

clientRequest(Seq,Operation) ->
    gen_server:cast(ps,{clientRequest,self(),Seq,Operation}),
    receive
        Message -> Message
    after
        1000 -> timeout
    end.
