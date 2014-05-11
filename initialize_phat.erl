-module(initialize_phat).
-export([init/1,init_count/2]).

start_phat_at_node(AllNodes) ->
    fun (NodeName) ->
      rpc:block_call(NodeName,
                     phat,
                     start_link,
                     [AllNodes])
    end.

init(N) ->
    SNames = [ list_to_atom("n" ++ integer_to_list(I) ++ "@localhost") || I <- lists:seq(1, N)],
    lists:map(start_phat_at_node(SNames), SNames).

init_count(N,C) ->
    SNames = [ list_to_atom("n" ++ integer_to_list(I) ++ "@localhost") || I <- lists:seq(N, N+C-1)],
    lists:map(start_phat_at_node(SNames), SNames).
