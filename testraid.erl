-module(testraid).

-export([test1/0,test2/0,putcontents/4]).

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

test2() ->
    client:start_link([n1@localhost,n2@localost,n3@localhost]),
    client:call({clear}),
    spawn(testraid, putcontents, [{handle, []}, [foo], barbar, self()]),
    spawn(testraid, putcontents, [{handle, []}, [bar], bazbaz, self()]),
    wait_for_resp(2,0).

putcontents(Handle, Name, Data, Pid) ->
    Make = client:call({mkfile,{handle,[]},Name, ""}),
    io:fwrite("Make ~p~n",[Make]),
    Resp = client:call({putcontents,{handle, Name},Data}),
    Pid ! Resp.

wait_for_resp(TotalNum, TotalNum) ->
    {ok};
wait_for_resp(TotalNum, Received) when Received < TotalNum ->
    receive
	ok ->
	    io:fwrite("Resp ~p~n",[ok]),
	    wait_for_resp(TotalNum, Received + 1);
	Resp ->
	    io:fwrite("Resp ~p~n",[Resp])
    end.
