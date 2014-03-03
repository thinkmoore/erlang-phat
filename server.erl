-module(server).
-behavior(gen_server).

-export([init/1,handle_call/3,handle_cast/2,terminate/2,code_change/3]).
-export([start_link/0,clientRequest/2,replicaCommit/1,stop/0]).

init(_) ->
    fs:start_link(),
    {ok,[]}.

handle_call({clientRequest,Seq,Operation},Client,State) ->
    case vr:handleClientRequest({Client,Seq,Operation}) of
        readyToCommit ->
            Result = gen_server:call(fs,Operation),
            vr:registerCommitted({Client,Seq,Result}),
            {reply, Result, State};
        {notMaster,Master} ->
            {reply, {notMaster,Master}, State}
    end;
handle_call({replicaCommit,Operation},_,State) ->
    Ret = gen_server:call(fs,Operation),
    {reply, Ret, State}.

handle_cast(stop, State) ->
    {stop, normal, State}.

terminate(Reason, _) ->
    io:fwrite("Phat server terminating! ~p~n", [Reason]),
    fs:stop().

code_change(_,_,_) ->
    {error, code_change_unsupported}.

start_link() ->
    gen_server:start_link({local, ps}, server, [], []).

stop() ->
    gen_server:cast(stop).

clientRequest(Seq,Operation) ->
    gen_server:call(ps,{clientRequest,Seq,Operation}).
replicaCommit(Operation) ->
    gen_server:call(ps,{replicaCommit,Operation}).
