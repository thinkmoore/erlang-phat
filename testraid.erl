-module(testraid).

-export([test1/0]).

%% % c(testraid), testraid:test1().
%% test1() ->
%%     raidclient:start_link([[n1@localhost,n2@localhost,n3@localhost],3]),
%%     Clear = client:call({clear}),
%%     io:fwrite("clear result: ~p~n",[Clear]),
%%     Store = raidclient:call({store,"name1","foobarbaz"}),
%%     io:fwrite("store result: ~p~n",[Store]),
%% %   Dump = client:call({dump}),
%% %    io:fwrite("dump result: ~p~n~n~n",[Dump]),
%%     Get = raidclient:call({get,"name1"}),
%%     io:fwrite("get result: ~p~n",[Get]),
%%     Store2 = raidclient:call({store,"name2","amanaplanacanalpanama"}),
%%     io:fwrite("store2 result: ~p~n",[Store2]),
%% %    Dump = client:call({dump}),
%%  %   io:fwrite("dump result: ~p~n~n~n",[Dump]),
%%     Get2 = raidclient:call({get,"name2"}),
%%     io:fwrite("get2 result: ~p~n",[Get2]),
%%     raidclient:stop().

%% % c(testraid), testraid:test2().
%% test2() ->
%%     raidclient:start_link([[n1@localhost,n2@localhost,n3@localhost],4]),
%%     Clear = client:call({clear}),
%%     io:fwrite("clear result: ~p~n",[Clear]),
%%     Store = raidclient:call({store,"name1","abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"}),
%%     io:fwrite("store result: ~p~n",[Store]),
%%     Get = raidclient:call({get,"name1"}),
%%     io:fwrite("get result: ~p~n",[Get]),
%%     raidclient:stop().

test1() ->
    raidclient:start_link([[n1@localhost,n2@localost,n3@localhost],[n1@localhost,n2@localost,n3@localhost],[n1@localhost,n2@localost,n3@localhost]]),
    Store = raidclient:call({store,"name1","abcdefghijklmnopqrstuvwxyz"}),
    io:fwrite("store result: ~p~n",[Store]),
    Get = raidclient:call({get,"name1"}),
    io:fwrite("get result: ~p~n",[Get]),
    raidclient:stop().
