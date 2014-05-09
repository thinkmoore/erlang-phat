-module(testraid).

-export([test1/0]).

% c(testraid), testraid:test1().
test1() ->
    raidclient:start_link([n1@localhost,n2@localhost,n3@localhost]),
    Clear = client:call({clear}),
    io:fwrite("clear result: ~p~n",[Clear]),
    Store = raidclient:call({store,"foobarbaz"}),
    io:fwrite("store result: ~p~n",[Store]),
    Dump = client:call({dump}),
    io:fwrite("dump result: ~p~n~n~n",[Dump]),
    Get = raidclient:call({get}),
    io:fwrite("get result: ~p~n",[Get]),
    raidclient:stop().

