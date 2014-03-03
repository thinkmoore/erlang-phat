-module(fs).
-behavior(gen_server).

-export([start_link/0,init/1,terminate/2]).
-export([code_change/3,handle_call/3,handle_cast/2,stop/0]).
-export([getroot/0,mkfile/3,open/2,getcontents/1,putcontents/2,readdir/1]).

getroot() ->
    gen_server:call(fs,{getroot}).
mkfile(Handle,SubPath,Data) ->
    gen_server:call(fs,{mkfile,Handle,SubPath,Data}).
readdir(Handle) ->
    gen_server:call(fs,{readdir,Handle}).
open(Handle,SubPath) ->
    gen_server:call(fs,{open,Handle,SubPath}).
getcontents(Handle) ->
    gen_server:call(fs,{getcontents,Handle}).
putcontents(Handle,Data) ->
    gen_server:call(fs,{putcontents,Handle,Data}).

start_link() ->
    gen_server:start_link({local, fs}, fs, [], []).
code_change(_,_,_) ->
    {error,code_change_unsupported}.
init(_) ->
    {ok,dict:store([],{dir, [], []},dict:new())}.
terminate(Reason,_) ->
    io:fwrite("Terminating! ~p~n", [Reason]).
stop() ->
    gen_server:cast(fs, stop).
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_,_) ->
    {error,async_unsupported}.

handle_call({getroot},_,State) ->
    {reply, getroot(State), State};
handle_call({open,Handle,SubPath},_,State) ->
    {reply, open(Handle,SubPath,State), State};
handle_call({mkfile,Handle,SubPath,Data},_,State) ->
    {Resp,NewState} = mkfile(Handle,SubPath,Data,State),
    {reply,Resp,NewState};
handle_call({readdir,Handle},_,State) ->
    {reply,readdir(Handle,State),State};
handle_call({getcontents,Handle},_,State) ->
    {reply,getcontents(Handle,State),State};
handle_call({putcontents,Handle,Data},_,State) ->
    {Resp,NewState} = putcontents(Handle,Data,State),
    {reply,Resp,NewState}.



%% State = { Map path := entry }  
%% entry = { file, lock_status, data } | {dir, lock_status, entry list}
%% path = reversed list of directories e.g. /dir1/dir2/filename = filename:dir2:dir1:[]
getroot(_) ->
    {ok,{handle, []}}.

open({handle,Path}, Subpath, State) ->
    Fullpath = lists:append(Subpath,Path),
    case dict:fetch(Fullpath,State) of
	error ->
	    {error,file_not_found};
	_ -> 
	    {ok,{handle,Fullpath}}
    end.

mkfile({handle,Path},Subpath,Data,State) ->
    [Name|Dirs] = lists:append(Subpath,Path),
    case dict:find([Name|Dirs],State) of
	error ->
	    case mkdirs(Dirs,State) of
		{{dir,Locks,Children},WithDirs} ->
		    NewState = dict:store(Dirs,{dir,Locks,[Name|Children]},WithDirs),
		    Handle = {ok,{handle,[Name|Dirs]}},
		    R = {Handle,dict:store([Name|Dirs], {file, [], Data},NewState)},
		    io:fwrite("~p~n",[R]),
		    R;
		Error -> {Error, State}
	    end;
	_ -> 
	    {{error,file_already_exists},State}
    end.
    
mkdirs([],State) ->
    {dict:fetch([],State),State};
mkdirs([H|Dirs],State) ->    
    case dict:find([H|Dirs],State) of
	error ->
	    case mkdirs(Dirs,State) of 
		{error, Message} ->
		    {error, Message};
		{{dir,Locks,Children},NewState} ->
		    NewDir = {dir,[],[]},
		    {NewDir,dict:store(Dirs,{dir,Locks,[H|Children]},NewState)}
	    end;				
	{ok,{dir,Locks,Children}} -> 
	    {{dir,Locks,Children},State};
	{ok,{file,_,_}} -> 
	    {error, {not_a_directory,[H|Dirs]}}
    end.

readdir({handle,Path},State) ->
    case dict:find(Path,State) of
	error ->
	    {error, file_not_found};
	{ok,{file, _, _}} ->
	    {error, not_a_directory};
	{ok,{dir, _, Stuff}} ->
	    {ok,Stuff}
    end.

getcontents({handle,Path},State) ->
    case dict:find(Path,State) of
	{ok, {file, _, Data}} ->
	    {ok, Data};
	{ok, {dir,_,_}} ->
	    {error, not_a_file};
	error -> 
	    {error, file_not_found}
    end.

putcontents({handle,Path},Data,State) ->
    case dict:find(Path,State) of
	{ok, {file,LockState,_}} ->
	    {ok,dict:store(Path,{file,LockState,Data},State)};
	{ok, {dir,_,_}} ->
	    {{error, not_a_file},State};
	error -> 
	    {{error, file_not_found},State}
    end.
