-module(raidclient).
-behavior(gen_server).
-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").
-export([start_link/1,init/1,handle_call/3,call/1,stop/0,handle_cast/2,terminate/2]).
-export([code_change/3,handle_info/2,xor_all/1,binary_bxor/2,store_chunk/5,get_chunk/4]).
-export([dotestloop/1,testloop/1]).
-export([profile/2]).

-define(TIMEOUT, 100000).
-define(MB_PER_BYTE, 1). 
-define(XOR_TIME_MB_PER_SEC, 20000).

% want Nodes to a list where each element is all the nodes for a single VR cluster
start_link(Clusters) ->
    NumChunks = length(Clusters),
    Clients = [list_to_atom("client" ++ [Num + 48]) || Num <- lists:seq(0, NumChunks-1)],
    lists:zipwith(fun (Cluster, Name) -> client:start_link(Cluster, Name) end, Clusters, Clients),
    gen_server:start_link({local,raid},raidclient,[Clients,NumChunks],[]).

init([Clients,NumChunks]) ->
    {ok, #{ clients => Clients, numchunks => NumChunks} }.

call(Operation) ->
    gen_server:call(raid,Operation,?TIMEOUT).

%% Server teardown
terminate(Reason,_) ->
    io:fwrite("Raid client terminating! Reason: ~p~n", [Reason]).
stop() ->
    call({stop}),
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
    WaitTime = max(S1,S2) / 8 * ?MB_PER_BYTE / ?XOR_TIME_MB_PER_SEC,
    io:fwrite("XOR wait time ~p seconds for ~p MB ~n", [WaitTime, max(S1, S2) / 8 * ?MB_PER_BYTE]),
    receive
    after
        trunc(WaitTime * 1000) -> ok
    end,
    I3 = I1 bxor I2,
    S3 = max(S1, S2),
    <<I3:S3>>.	       

binary_to_chunks(B,G) ->
    Size = byte_size(B) div (G-1),
    Splits = do_split_binary(Size, B),
    Xor = xor_all(Splits),
    [Xor|Splits].

store_chunk(Client,Chunk,Name,Num,Pid) ->
    client:call(Client,{mkfile,{handle,[]},[Name, Num],""}),
    Resp = client:call(Client,{putcontents,{handle,[Name, Num]},Chunk}),
    Pid ! Resp.

store_chunks(Clients,Chunks,TotalNum,Name) ->
    lists:zipwith3(fun (Client, Chunk, Num) ->
			  spawn(raidclient, store_chunk, [Client,Chunk,Name,Num,self()]) end, 
		          Clients, Chunks, lists:seq(0, TotalNum - 1)),
    wait_for_store(TotalNum, 0).

wait_for_store(TotalNum, TotalNum) ->
    {ok};
wait_for_store(TotalNum, Received) when Received < TotalNum ->
    receive
	ok ->
	    wait_for_store(TotalNum, Received + 1);
	Resp ->
            io:fwrite("Response was ~p~n", [Resp]),
     	    terminate("Didn't receive ok from a store",{})
    after
     	?TIMEOUT ->
     	    terminate("timeout waiting for store chunks",{})
    end.

get_chunk(Client, Name, Num, Pid) ->
    Block = client:call(Client, {getcontents,{handle,[Name,Num]}}),
    Pid ! {Block, Num}.

get_chunks(Clients,TotalNum,Name) ->
    lists:map(fun ({Client,Num}) -> spawn(raidclient, get_chunk, [Client,Name,Num,self()]) end,
	      lists:zip(Clients, lists:seq(0, TotalNum - 1))),
    wait_for_chunks(TotalNum, 0, []).

wait_for_chunks(TotalNum, TotalNum, Acc) ->
    lists:map(fun ({B,_}) -> B end, lists:keysort(2,Acc));
wait_for_chunks(TotalNum, Received, Acc) when Received < TotalNum ->
    receive
	{Block, N} ->
	    wait_for_chunks(TotalNum, Received + 1, [{Block,N}|Acc])
    after
     	?TIMEOUT ->
     	    terminate("timeout waiting for get chunks", {})
    end.

handle_call({store,Name,Data},_,State = #{ clients := Clients, numchunks := N}) ->
    Binary = binary:list_to_bin(Data),
    Chunks = binary_to_chunks(Binary,N),
    ?debugFmt("chunks: ~p~n", [Chunks]),
    Store = store_chunks(Clients, Chunks, N, Name),
    ?debugFmt("stored: ~p~n", [Store]),
    {reply, Store, State};
handle_call({get,Name},_,State = #{ clients := Clients, numchunks := TotalNum}) ->
    %[Check|Chunks] = lists:reverse(get_chunks(Clients,Name)),
    [Check|Chunks] = get_chunks(Clients,TotalNum,Name),
    ?debugFmt("~p~n", [[Check|Chunks]]),
    Data = lists:foldl(fun (E,Acc) -> << Acc/binary, E/binary >> end, <<>>, Chunks),
    ?debugFmt("~p~n", [binary_to_list(Data)]),
    Check1 = xor_all(Chunks),
    if 
	Check =:= Check1 ->
	    ?debugFmt("~p~n", ["Parity check passes!"]),
	    ok;
	true -> 
	    io:fwrite("~p~n", ["Parity check failed!"])
    end,
    {reply, Data, State};

handle_call({clear},_, State = #{ clients := Clients}) ->
    lists:map(fun (Client) -> gen_server:call(Client,{clear}) end, Clients),
    {reply, ok, State};

handle_call({stop},_,State = #{ clients := Clients}) ->
    lists:map(fun (Client) -> gen_server:cast(Client,stop) end, Clients),
    {reply, stopped, State}.   



profile(Filesize, Trials) ->
    File = [48 || Num <- lists:seq(0, Filesize-1)],
    lists:map(fun(I) ->
        {TimeStore, ValueStore} = timer:tc(fun call/1, [{store, "file" ++ I + 48, File}]),
        {TimeFetch, ValueFetch} = timer:tc(fun call/1, [{get, "file" ++ I + 48}]),

        ValueFetch2 = binary_to_list(ValueFetch),
        if
            ValueFetch2 =/= File ->
                io:fwrite("didn't get back same file ~p ~n", [ValueFetch]);
            true -> ok
        end,
        io:fwrite("Store Time: ~p ms -- Fetch Time: ~p ms ~n", [TimeStore / 1000, TimeFetch / 1000])
    end, lists:seq(1, Trials)),
    call({clear}).

test() ->
    Store = raidclient:call({store,"name1","abcdefghijklmnopqrstuvwxyz"}),
    Get = raidclient:call({get,"name1"}).

testloop(0) ->
    ok;
testloop(N) ->
    test(),
    testloop(N-1).

dotestloop(N) ->
    timer:tc(raidclient, testloop, [N]).
