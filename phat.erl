-module(phat).
-behavior(supervisor).

-export([init/1,start_link/1,inject_fault/1,stop/0,restart/0,test/0]).

init([Master|Rest]) ->
    Node = node(),
    VRS = lists:map(fun (N) -> {vr,N} end, [Master|Rest]),
    {ok, {{one_for_all, 1, 5},
          [{fs, {fs, start_link, []}, permanent, 1, worker, [fs]}
          ,{ps, {server, start_link, []}, permanent, 1, worker, [server]}
          ,{vr, {vr, startNode, [{vr,Node}, VRS, fun server:commit/3]},
            permanent, 1, worker, [vr]}]}}.

start_link(Nodes) ->
    supervisor:start_link({local, phat}, phat, Nodes).

inject_fault(fs) ->
    gen_fsm:send_event(fs, {die});
inject_fault(ps) ->
    gen_server:cast(ps, {die});
inject_fault(vr) ->
    gen_fsm:send_event(vr, {die}).
    
stop() ->
    supervisor:terminate_child(phat, vr),
    supervisor:terminate_child(phat, ps),
    supervisor:terminate_child(phat, fs).

restart() ->
    supervisor:restart_child(phat, vr),
    supervisor:restart_child(phat, ps),
    supervisor:restart_child(phat, fs).

test() ->
    {0,{ok,Root}} = server:clientRequest(0,{getroot}),
    {1,{ok,Hello}} = server:clientRequest(1,{mkfile,Root,["hello"],"Hello world!"}),
    {2,{ok,"Hello world!"}} = server:clientRequest(2,{getcontents,Hello}).
