-module(testfs).

-export([test1/0,testLock/0,testTimeout/0,testRefresh/0,getLock/2,testClient/0]).

test1() ->
    fs:stop(),
    fs:start_link(),
    {ok,Root} = fs:getroot(),
    {ok,H} = fs:mkfile(Root,["hey there"],"Hello there"),
    {ok,Initial} = fs:getcontents(H),
    fs:putcontents(H,"I'm out"),
    {ok,Final} = fs:getcontents(H),
    {Initial,Final}.

testLock() ->
    fs:start_link(),
    {ok,Root} = fs:getroot(),
    {ok,H} = fs:mkfile(Root,["heythere.txt","dir2", "dir1"], "Hello there"),
    fs:remove(H),
    fs:open(H,[]), %% error
    {ok,H2} = fs:mkfile(Root,["heythere.txt","dir2", "dir1"], "My good friend!"),
    {ok,S1} = fs:flock(H2,read,1),
    io:fwrite("seq1 ~p~n~n", [S1]),
    {ok,S2} = fs:flock(H2,read,1),
    io:fwrite("seq2 ~p~n~n", [S2]),
    {error,S3} = fs:flock(H2,write,1), %% error
    io:fwrite("seq3 ~p~n~n", [S3]),
    {ok,S4} = fs:funlock(H2),
    io:fwrite("seq4 ~p~n~n", [S4]),
    {ok,S5} = fs:funlock(H2),
    io:fwrite("seq5 ~p~n~n", [S5]),
    {ok,S6} = fs:flock(H2,write,1),
    io:fwrite("seq6 ~p~n~n", [S6]),
    {ok,S7} = fs:funlock(H2),
    io:fwrite("seq7 ~p~n~n", [S7]),
    fs:stop().
    
getLock(From,H) ->
    case fs:flock(H,write,1) of
        {ok,S} ->
            io:fwrite("got a lock on ~p: ~p~n", [H,S]),
            From ! {gotit,S};
        Msg ->
            io:fwrite("flock failed ~p~n", [Msg]),
            receive after 1000 -> getLock(From, H) end
    end.    

testTimeout() ->
    fs:start_link(),
    {ok,Root} = fs:getroot(),
    {ok,_} = fs:mkfile(Root,["bar","baz","quux"],"!!!"),
    {ok,_} = fs:mkfile(Root,["foo", "dir1"],"stuff"),
    {ok,H} = fs:mkdir(Root,["dir2", "dir1"]),
    io:fwrite("mkdir result: ~p~n", [H]),
    {ok,S} = fs:flock(H,write,2),
    spawn(testfs, getLock, [self(),H]),
    receive
        {gotit,S2} ->
            io:fwrite("S: ~p S2: ~p~n", [S,S2])
    after
        5000 ->
            io:fwrite("hung~n")
    end,
    fs:stop().

testRefresh() ->
    fs:start_link(),
    {ok,Root} = fs:getroot(),
    {ok,_} = fs:flock(Root,read,1),
    spawn(testfs, getLock, [self(), Root]),
    fs:refreshlock(Root,5),
    receive
        {gotit,_} ->
            io:fwrite("got the lock~n")
    after
        3000 -> 
            io:fwrite("hung~n")
    end,
    fs:stop().

testClient() ->
    client:start(),
    Root = client:call({getroot}),
    H = client:call({mkfile,Root,["bar","baz","quux"],"!!!"}),
    io:fwrite("mkfile result: ~p~n", [H]),
    S = client:call({flock,H,write,2}),
    io:fwrite("flock result: ~p~n", [S]),
    S2 = client:call({flock,H,write,2}),
    io:fwrite("flock result: ~p~n", [S2]),
    client:call({remove,H}).
    
