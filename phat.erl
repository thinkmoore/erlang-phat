-module(phat).
-behavior(supervisor).

-export([init/1,start_link/1,inject_fault/1]).

init([Master|Rest]) ->
    Node = node(),
    VRM = {vr,Master},
    VRS = lists:map(fun (N) -> {vr,N} end, [Master|Rest]),
    {ok, {{one_for_all, 1, 5},
          [{fs, {fs, start_link, []}, permanent, 1, worker, [fs]}
          ,{ps, {server, start_link, []}, permanent, 1, worker, [server]}
          ,{vr, {vr, startNode, [{vr,Node}, VRM, VRS, fun server:commit/3]},
            permanent, 1, worker, [vr]}]}}.

start_link(Nodes) ->
    supervisor:start_link({local, phat}, phat, Nodes).

inject_fault(fs) ->
    gen_fsm:send_event(fs, {die});
inject_fault(ps) ->
    gen_server:cast(ps, {die});
inject_fault(vr) ->
    gen_fsm:send_event(vr, {die}).
    
