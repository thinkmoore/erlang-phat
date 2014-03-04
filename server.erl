-module(server).
-behavior(gen_server).

-export([init/1,handle_cast/2,terminate/2,code_change/3]).
-export([start_link/1,clientRequest/2,stop/0]).

init([Master|Rest]) ->
    fs:start_link(),
    vr:startNode({vr,node()}, {vr,Master}, lists:map(fun (N) -> {vr,N} end, [Master|Rest]), fun commit/3),
    {ok,[]}.

commit(_, Op, NodeType) ->
    Ret = gen_server:call(fs,Op),
    io:fwrite("Commited ~p as ~p on ~p~n", [Ret,NodeType,node()]),
    {reply, Ret}.

handle_cast({clientRequest,From,Seq,Operation},State) ->
    vr:startPrepare({vr,node()},From,Seq,Operation),
    {noreply,State};
handle_cast(stop, State) ->
    {stop, normal, State}.

terminate(Reason, _) ->
    io:fwrite("Phat server terminating! ~p~n", [Reason]),
    fs:stop().

code_change(_,_,_) ->
    {error, code_change_unsupported}.

start_link(Nodes) ->
    gen_server:start_link({local, ps}, server, Nodes, []).

stop() ->
    gen_server:cast(stop).

clientRequest(Seq,Operation) ->
    gen_server:cast(ps,{clientRequest,self(),Seq,Operation}),
    receive
        Message -> Message
    after
        1000 -> timeout
    end.
