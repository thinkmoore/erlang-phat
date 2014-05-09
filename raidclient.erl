-module(raidclient).
-behavior(gen_server).
%-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").
-export([start_link/1,init/1,handle_call/3,call/1,stop/0,handle_cast/2,terminate/2]).

start_link(Nodes) ->
    gen_server:start_link({local,raid},raidclient,Nodes,[]).

init(Nodes) ->
    client:start_link(Nodes),
    {ok, #{ chunks => 3} }.

call(Operation) ->
    gen_server:call(raid,Operation).

%% Server teardown
terminate(Reason,_) ->
    io:fwrite("Raid client terminating! Reason: ~p~n", [Reason]).
stop() ->
    gen_server:cast(raid, stop).

%% Unimplemented call backs
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_,_) ->
    {error,async_unsupported}.

do_split_binary(Size, B) when byte_size(B) >= Size->
    {Chunk, Rest} = split_binary(B, Size),
    [ Chunk | do_split_binary(Size, Rest) ];
do_split_binary(_, <<>>) ->
    [];
do_split_binary(_, B)  ->
    [ B ].

xor_all([Chunk]) ->
    Chunk;
xor_all([H|Rest]) ->
    XorRest = xor_all(Rest),
    list_to_binary([X bxor Y || X <- binary_to_list(XorRest), Y <- binary_to_list(H)]).    

binary_to_chunks(B,G) ->
    Size = byte_size(B) div G,
    Splits = do_split_binary(Size, B),
    Xor = xor_all(Splits),
    [Xor|Splits].

do_chunk(Chunk,Num) ->
    client:call({mkfile,{handle,[]},[Num],""}),
    client:call({putcontents,{handle,[Num]},Chunk}),
    Num + 1.

get_chunk(Num) ->
    client:call({getcontents,{handle,[Num]}}).

get_chunks(0) ->
    [get_chunk(0)];
get_chunks(N) ->
    [get_chunk(N)|get_chunks(N-1)].

handle_call({store,Data},_,State = #{ chunks := G}) ->
    Binary = binary:list_to_bin(Data),
    Parts = binary_to_chunks(Binary,G),
    lists:foldl(fun do_chunk/2, 0, Parts),
    {reply, done, State};
handle_call({get},_,State = #{ chunks := G}) ->
    [Check|Parts] = lists:reverse(get_chunks(G)),
    io:fwrite("~p~n", [[Check|Parts]]),
    Data = lists:foldl(fun (E,Acc) -> << Acc/binary, E/binary >> end, <<>>, Parts),
    io:fwrite("~p~n", [binary_to_list(Data)]),
    Check = xor_all(Parts),
    {reply, Data, State}.
    
