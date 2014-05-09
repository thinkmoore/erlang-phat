-module(raidclient).
-behavior(gen_server).
%-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").
-export([start_link/1,init/1,handle_call/3,call/1,stop/0,handle_cast/2,terminate/2]).
-export([code_change/3,handle_info/2,xor_all/1,binary_bxor/2]).

start_link([Nodes,NumChunks]) ->
    gen_server:start_link({local,raid},raidclient,[Nodes,NumChunks],[]).

init([Nodes,NumChunks]) ->
    client:start_link(Nodes),
    {ok, #{ chunks => NumChunks} }.

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
code_change(_,_,_) ->
    {error,code_change_unsupported}.
handle_info(_,_) ->
    {error,info_unsupported}.

do_split_binary(Size, B) when byte_size(B) >= 2*Size->
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
    binary_bxor(H, XorRest).

binary_bxor(B1, B2) ->
    S1 = size(B1)*8,
    S2 = size(B2)*8,
    <<I1:S1>> = B1,
    <<I2:S2>> = B2,
    I3 = I1 bxor I2,
    S3 = max(S1, S2),
    <<I3:S3>>.	       

binary_to_chunks(B,G) ->
    Size = byte_size(B) div G,
    Splits = do_split_binary(Size, B),
    Xor = xor_all(Splits),
    [Xor|Splits].

do_chunk_helper (Name) -> 
    Helper = 
	fun (Chunk,Num) -> 
	    do_chunk(Chunk,Name,Num), 
	    Num + 1 end,
    Helper.

do_chunk(Chunk,Name,Num) ->
    client:call({mkfile,{handle,[]},[Name, Num],""}),
    client:call({putcontents,{handle,[Name, Num]},Chunk}).

get_chunk(Name,Num) ->
    client:call({getcontents,{handle,[Name,Num]}}).

get_chunks(Name,0) ->
    [get_chunk(Name,0)];
get_chunks(Name,N) ->
    [get_chunk(Name,N)|get_chunks(Name,N-1)].

handle_call({store,Name,Data},_,State = #{ chunks := G}) ->
    Binary = binary:list_to_bin(Data),
    Parts = binary_to_chunks(Binary,G),
    io:fwrite("~p~n", [Parts]),
    lists:foldl(do_chunk_helper(Name), 0, Parts),
    {reply, done, State};
handle_call({get,Name},_,State = #{ chunks := G}) ->
    [Check|Parts] = lists:reverse(get_chunks(Name,G)),
    ?debugFmt("~p~n", [[Check|Parts]]),
    Data = lists:foldl(fun (E,Acc) -> << Acc/binary, E/binary >> end, <<>>, Parts),
    ?debugFmt("~p~n", [binary_to_list(Data)]),
    Check1 = xor_all(Parts),
    if 
	Check =:= Check1 ->
	    io:fwrite("~p~n", ["Parity check passes!"]);
	true -> 
	    io:fwrite("~p~n", ["Parity check failed!"])
    end,
    {reply, Data, State}.
    
