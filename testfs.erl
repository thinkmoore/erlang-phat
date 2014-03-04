-module(testfs).

-export([test1/0,testLock/0]).

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
    S1 = fs:flock(H2,read),
    io:fwrite("seq1 ~p~n~n", [S1]),
    S2 = fs:flock(H2,read),
    io:fwrite("seq2 ~p~n~n", [S2]),
    S3 = fs:flock(H2,write), %% error
    io:fwrite("seq3 ~p~n~n", [S3]),
    S4 = fs:funlock(H2),
    io:fwrite("seq4 ~p~n~n", [S4]),
    S5 = fs:funlock(H2),
    io:fwrite("seq5 ~p~n~n", [S5]),
    S6 = fs:flock(H2,write),
    io:fwrite("seq6 ~p~n~n", [S6]),
    S7 = fs:funlock(H2),
    io:fwrite("seq7 ~p~n~n", [S7]),
    fs:stop().
    
