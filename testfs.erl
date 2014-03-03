-module(testfs).

-export([test1/0]).

test1() ->
    fs:stop(),
    fs:start_link(),
    {ok,Root} = fs:getroot(),
    {ok,H} = fs:mkfile(Root,["hey there"],"Hello there"),
    {ok,Initial} = fs:getcontents(H),
    fs:putcontents(H,"Dan needs to go"),
    {ok,Final} = fs:getcontents(H),
    {Initial,Final}.
    
