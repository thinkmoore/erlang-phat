-module(initialize_phat).
-export([init/1]).

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

