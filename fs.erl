-module(fs).
-behavior(gen_server).
-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").

-export([start_link/0,init/1,terminate/2]).
-export([code_change/3,handle_call/3,handle_cast/2,stop/0,handle_info/2]).
-export([getroot/0,mkfile/3,open/2,getcontents/1,putcontents/2,readdir/1]).
-export([mkdir/2,stat/1,flock/2,funlock/1,remove/1]).

%% Calls into the server
getroot() ->
    gen_server:call(fs,{getroot}).
open(Handle,SubPath) ->
    gen_server:call(fs,{open,Handle,SubPath}).
mkfile(Handle,SubPath,Data) ->
    gen_server:call(fs,{mkfile,Handle,SubPath,Data}).
mkdir(Handle,SubPath) ->
    gen_server:call(fs,{mkdir,Handle,SubPath}).
getcontents(Handle) ->
    gen_server:call(fs,{getcontents,Handle}).
putcontents(Handle,Data) ->
    gen_server:call(fs,{putcontents,Handle,Data}).
readdir(Handle) ->
    gen_server:call(fs,{readdir,Handle}).
stat(Handle) ->
    gen_server:call(fs,{stat,Handle}).
flock(Handle, LockType) ->
    gen_server:call(fs,{flock,Handle, LockType}).
funlock(Handle) ->
    gen_server:call(fs,{funlock,Handle}).
remove(Handle) ->
    gen_server:call(fs,{remove,Handle}).


%% Server startup
start_link() ->
    gen_server:start_link({local, fs}, fs, [], []).
init(_) ->
    {ok,dict:store([],{dir, [], []},dict:new())}.

%% Server teardown
terminate(Reason,_) ->
    io:fwrite("Terminating! ~p~n", [Reason]).
stop() ->
    gen_server:cast(fs, stop).

%% Unimplemented call backs
code_change(_,_,_) ->
    {error,code_change_unsupported}.
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_,_) ->
    {error,async_unsupported}.
handle_info(_,_) ->
    {error, info_unsupported}.

%% Server call backs
handle_call({getroot},_,State) ->
    {reply, getroot(State), State};
handle_call({open,Handle,SubPath},_,State) ->
    {reply, open(Handle,SubPath,State), State};
handle_call({mkfile,Handle,SubPath,Data},_,State) ->
    {Resp,NewState} = mkfile(Handle,SubPath,Data,State),
    {reply,Resp,NewState};
handle_call({mkdir,Handle,SubPath},_,State) ->
    {Resp,NewState} = mkdir(Handle,SubPath,State),
    {reply,Resp,NewState};
handle_call({getcontents,Handle},_,State) ->
    {reply,getcontents(Handle,State),State};
handle_call({putcontents,Handle,Data},_,State) ->
    {Resp,NewState} = putcontents(Handle,Data,State),
    {reply,Resp,NewState};
handle_call({readdir,Handle},_,State) ->
    {reply,readdir(Handle,State),State};
handle_call({stat,Handle},_,State) ->
    {reply,stat(Handle,State),State};
handle_call({flock,Handle,LockType},_,State) ->
    {Resp,NewState} = flock(Handle,LockType,State),
    {reply,Resp,NewState};
handle_call({funlock,Handle},_,State) ->
    {Resp,NewState} = funlock(Handle,State),
    {reply,Resp,NewState};
handle_call({remove,Handle},_,State) ->
    {Resp,NewState} = remove(Handle,State),
    {reply,Resp,NewState}.

%% State = { Map path := entry }  
%% entry = { file, lock_status, data } | {dir, lock_status, entry list}
%% path = reversed list of directories e.g. /dir1/dir2/filename = filename:dir2:dir1:[]
%% Locks = {read={curReadSeqNum,numLocksStillHeld},write={curWriteSeqNum,locked/unlocked}}
%% Sequencer = {type=read/write,path=Path,sequenceNum=monotonically increasing counter}

%% Functions that actually do stuff
getroot(_) ->
    {ok,{handle, []}}.

open({handle,Path}, Subpath, State) ->
    Fullpath = lists:append(Subpath,Path),
    case dict:find(Fullpath,State) of
	error ->
	    ?debugFmt("file not found in open: ~p~n",[Fullpath]),
	    {error,file_not_found};
	_ -> 
	    ?debugFmt("opened: ~p~n",[Fullpath]),
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
		    NewLocks = #{read => {0, 0}, write => {0, unlocked}},
		    FinalState = dict:store([Name|Dirs], {file,NewLocks,Data}, NewState),
		    ?debugFmt("mkfile final state: ~n~p~n", [NewState]),
		    {Handle,FinalState};
	      	Error -> 
		    ?debugFmt("mkfile, error making dirs ~p~n", [Error]),
		    {Error, State}
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
		    NewDir = {dir,#{read => {0, []}, write => {0, unlocked}},[]},
		    {NewDir,dict:store(Dirs,{dir,Locks,[H|Children]},NewState)}
	    end;				
	{ok,{dir,Locks,Children}} -> 
	    {{dir,Locks,Children},State};
	{ok,{file,_,_}} -> 
	    {error, {not_a_directory,[H|Dirs]}}
    end.

mkdir({handle,Path},Subpath,State) ->
    Dirs = lists:append(Subpath,Path),
    case dict:find(Dirs,State) of
	error ->
	    case mkdirs(Dirs,State) of
		{{dir,_,_},WithDirs} ->
		    Handle = {ok,{handle,WithDirs}},
		    ?debugFmt("mkdir final state: ~n~p~n", [WithDirs]),
		    {Handle,WithDirs};
		Error ->
		    {Error,State}
	    end;
	_  ->
	    {{error,directory_already_exists},State}
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
	    NewState = dict:store(Path,{file,LockState,Data},State),
	    ?debugFmt("mkdir final state: ~p~n~p~n", [Path,NewState]),
	    {ok,NewState};
	{ok, {dir,_,_}} ->
	    {{error, not_a_file},State};
	error -> 
	    {{error, file_not_found},State}
    end.

stat({handle,Path},State) ->
    case dict:find(Path,State) of
	{ok, {file, Locks, _}} ->
	    {ok, {"file", Locks}}; 
	{ok, {dir, Locks, _}} ->
	    {ok, {"dir",Locks}};
	error ->
	    {error, file_or_dir_not_found}
    end.

flock({handle,Path},LockType,State) ->
    case dict:find(Path,State) of
	error ->
	    {{error, file_or_dir_not_found},State};
	{ok, {Type, Locks, DataOrChildren}} ->
	    #{read := {ReadSeq,NumRead}, write := {WriteSeq,WriteStatus}} = Locks,
	    case {WriteStatus, LockType} of
		{locked, _} ->
		    ?debugFmt("ERROR flock with existing write: ~p~n~p~n", [Path,State]),
		    {{error, already_write_locked},State};
		{unlocked,read} ->
		    NewLocks = Locks#{read := {ReadSeq,NumRead+1}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {read, {handle,Path}, ReadSeq},
		    ?debugFmt("flock read final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};		
		{unlocked,write} when NumRead =:= 0 ->
		    NewLocks = Locks#{write := {WriteSeq,locked}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {write, {handle,Path}, WriteSeq},
		    ?debugFmt("flock write final state ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};
		{unlocked,write} -> 
		    ?debugFmt("ERROR flock write with existing read: ~p~n~p~n", [Path,State]),
		    {{error, already_read_locked},State}
	    end
    end.

funlock({handle,Path},State) ->
    case dict:find(Path,State) of
	error ->
	    {{error, file_or_dir_not_found},State};
	{ok, {Type, Locks, DataOrChildren}} ->
	    #{read := {ReadSeq,NumRead}, write := {WriteSeq,WriteStatus}} = Locks,
	    case WriteStatus of
		locked ->
		    NewLocks = Locks#{write := {WriteSeq+1,unlocked}},
                    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {write, {handle,Path}, WriteSeq+1},
		    ?debugFmt("funlock final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};
		unlocked when NumRead > 0 ->
		    %% Read locked
		    NewLocks = Locks#{read := {ReadSeq+1,NumRead-1}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {read, {handle,Path}, ReadSeq+1},
		    ?debugFmt("funlock final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};
		unlocked ->
		    ?debugFmt("ERROR funlock not locked: ~p~n~p~n", [Path,State]),
		    {{error, file_or_dir_not_locked},State}
	    end
    end.

remove({handle,Path},State) ->
    case dict:find(Path,State) of
	error ->
	    {{error, file_or_dir_not_found},State};
	{ok, {file,_,_}} ->
	    NewState = dict:erase(Path,State),
	    [Name|PathTo] = Path,
	    %% assuming the parent is here
	    {ok, {dir,Locks,Children}} = dict:find(PathTo,State),
	    %% TODO is keydelete slow?
	    NewChildren = Children--[Name],
	    NewNewState = dict:store(PathTo,{dir,Locks,NewChildren},NewState),
	    ?debugFmt("remove final state: ~p~n~p~n", [Path,NewNewState]),
	    {ok,NewNewState};
	{ok, {dir,_,Children}} ->
	    case Children of
		[] ->
		    NewState = dict:erase(Path,State),
		    [Name|PathTo] = Path,
		    %% assuming the parent is here
		    {ok, {dir,Locks,Children}} = dict:find(PathTo,State),
		    %% TODO is keydelete slow?
		    NewChildren = Children--[Name],
		    NewNewState = dict:store(PathTo,{dir,Locks,NewChildren},NewState),
		    ?debugFmt("remove final state: ~p~n~p~n", [Path,NewNewState]),
		    {ok,NewNewState};
		_ ->
		    ?debugFmt("ERROR nonempty dir: ~p~n~p~n", [Path,State]),
		    {{error, cannot_remove_nonempty_dir},State}
	    end
    end.
		    
