-module(fs).
-behavior(gen_server).
-define(NODEBUG, true). %% comment out for debugging messages
-include_lib("eunit/include/eunit.hrl").

-export([start_link/0,init/1,terminate/2]).
-export([code_change/3,handle_call/3,handle_cast/2,stop/0,handle_info/2]).
-export([getroot/0,mkfile/3,open/2,getcontents/1,putcontents/2,readdir/1]).
-export([mkdir/2,stat/1,flock/3,refreshlock/2,funlock/1,remove/1,checktimeout/2,forcelock/3,dontlock/1]).
-export([dump/0,clear/0, fswritedelay/1]).

%% Disk latency simulation constants
-define(MB_PER_CHAR, 500).
-define(DISK_WRITE_THRUPUT_MB_S, 200.0).
-define(DISK_WRITE_ACCESS_TIME_S, 0.03).
-define(DISK_READ_THRUPUT_MB_S, 200.0).
-define(DISK_READ_ACCESS_TIME_S, 0.03).

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
flock(Handle, LockType, Timeout) ->
    gen_server:call(fs,{flock,Handle,LockType,Timeout}).
forcelock(Handle, LockType, Timeout) ->
    gen_server:call(fs,{forcelock,Handle,LockType,Timeout}).
dontlock(Handle) ->
    gen_server:call(fs,{dontlock,Handle}).
checktimeout(Handle, LockType) ->
    gen_server:call(fs,{checktimeout,Handle, LockType}).
funlock(Handle) ->
    gen_server:call(fs,{funlock,Handle}).
refreshlock(Handle,Timeout) ->
    gen_server:call(fs,{refreshlock,Handle,Timeout}).
remove(Handle) ->
    gen_server:call(fs,{remove,Handle}).
% get the whole file system
dump() ->
    gen_server:call(fs,{dump}).
% remove all files
clear() ->
    gen_server:call(fs,{clear}).


%% Server startup
start_link() ->
    gen_server:start_link({local, fs}, fs, [], []).
init(_) ->
    io:fwrite("Starting fileystem on ~p~n", [node()]),
    Fresh = fresh(),
    {ok,Fresh}.

fresh() ->
    dict:store([],{dir, #{read => {0, 0, {0,0,0}}, write => {0, unlocked}}, []},dict:new()).
    

%% Server teardown
terminate(Reason,_) ->
    io:fwrite("Filesystem terminating! Reason: ~p~n", [Reason]).
stop() ->
    gen_server:cast(fs, stop).

%% Unimplemented call backs
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_,_) ->
    {error,async_unsupported}.
code_change(_,_,_) ->
    {error,code_change_unsupported}.
handle_info(_,_) ->
    {error,info_unsupported}.

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
handle_call({flock,Handle,LockType,Timeout},_,State) ->
    {Resp,NewState} = flock(Handle,LockType,Timeout,State),
    {reply,Resp,NewState};
handle_call({forcelock,Handle,LockType,Timeout},_,State) ->
    {Resp,NewState} = forcelock(Handle,LockType,Timeout,State),
    {reply,Resp,NewState};
handle_call({dontlock, Handle},_,State) ->
    {reply, dontlock(Handle, State), State};
handle_call({checktimeout,{handle,Path},LockType},_,State) ->
    {reply, checktimeout({handle,Path},LockType,State), State};
handle_call({funlock,Handle},_,State) ->
    {Resp,NewState} = funlock(Handle,State),
    {reply,Resp,NewState};
handle_call({refreshlock,Handle,Timeout},_,State) ->
    {Resp,NewState} = refreshlock(Handle,Timeout,State),
    {reply,Resp,NewState};
handle_call({remove,Handle},_,State) ->
    {Resp,NewState} = remove(Handle,State),
    ?debugFmt("remove response: ~p~n", [Resp]),
    {reply,Resp,NewState};
handle_call({dump},_,State) ->
    {reply,{ok,State},State};
handle_call({clear},_,_) ->
    Fresh = fresh(),
    {reply,{ok,clear},Fresh};
handle_call(OpName,_,State) ->
    {reply, {error, {illegal_fs_operation, OpName}}, State}.


%% State = { Map path := entry }  
%% entry = { file, lock_status, data } | {dir, lock_status, entry list}
%% path = reversed list of directories e.g. /dir1/dir2/filename = filename:dir2:dir1:[]
%% Locks = {read={SeqNum,Count,Expiration}, write={SeqNum,Expiration} | {SeqNum,unlocked}}
%% Sequencer = {type=read/write,path=Path,sequenceNum=monotonically increasing counter}

%% FS hard disk delay simulator


fswritedelay(Data) ->
    WaitTime = byte_size(Data) * (?MB_PER_CHAR / ?DISK_WRITE_THRUPUT_MB_S) + ?DISK_WRITE_ACCESS_TIME_S,
    io:fwrite("writing a file of size ~p MB, will take ~p seconds ~n", [byte_size(Data) * ?MB_PER_CHAR, WaitTime]),
    
    receive
    after
        trunc(WaitTime * 1000) -> ok
    end.

fsreaddelay(Data) ->
    WaitTime = byte_size(Data) * (?MB_PER_CHAR / ?DISK_READ_THRUPUT_MB_S) + ?DISK_READ_ACCESS_TIME_S,
    io:fwrite("reading a file of size ~p MB, will take ~p seconds ~n", [byte_size(Data) * ?MB_PER_CHAR, WaitTime]),
    receive
    after
        trunc(WaitTime * 1000) -> ok
    end.


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
		    NewLocks = #{read => {0, 0, {0,0,0}}, write => {0, unlocked}},
		    FinalState = dict:store([Name|Dirs], {file,NewLocks,Data}, NewState),
		    ?debugFmt("mkfile final state: ~n~p~n", [FinalState]),
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
		    NewDir = {dir,#{read => {0, 0, {0,0,0}}, write => {0, unlocked}},[]},
                    InParent = dict:store(Dirs,{dir,Locks,[H|Children]},NewState),
		    {NewDir,dict:store([H|Dirs],NewDir,InParent)}
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
		    Handle = {ok,{handle,Dirs}},
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
        fsreaddelay(Data),
	    {ok, Data};
	{ok, {dir,_,_}} ->
	    {error, not_a_file};
	error -> 
	    {error, file_not_found}
    end.

putcontents({handle,Path},Data,State) ->
    fswritedelay(Data),
    case dict:find(Path,State) of
	{ok, {file,LockState,_}} ->
	    NewState = dict:store(Path,{file,LockState,Data},State),
	    ?debugFmt("mkdir final state: ~p~n~p~n", [Path,NewState]),
	    {{ok, ok},NewState};
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

addseconds({Mega,Sec,Micro},Seconds) ->
    NewSeconds = Seconds + Sec,
    if
        NewSeconds > 1000000 ->
            {Mega+1,NewSeconds - 1000000,Micro};
        true ->
            {Mega,NewSeconds, Micro}
    end.

flock({handle,Path},LockType,Timeout,State) ->
    Now = now(),
    case dict:find(Path,State) of
	error ->
	    {{error, file_or_dir_not_found},State};
	{ok, {Type, Locks, DataOrChildren}} ->
	    #{read := {ReadSeq,NumRead,Expires}, write := {WriteSeq,WriteStatus}} = Locks,
            NewExpires = addseconds(Now,Timeout),
	    case {WriteStatus, LockType} of
		{unlocked,read} ->
                    NewExpiration = max(Expires,NewExpires),
                    NewSeq = if NumRead =:= 0 ->
                                     ReadSeq + 1;
                                true ->
                                     ReadSeq
                             end,
		    NewLocks = Locks#{read := {NewSeq,NumRead+1,NewExpiration}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {read, {handle,Path}, NewSeq},
		    ?debugFmt("flock read final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};		
		{unlocked,write} when NumRead =:= 0 ->
		    NewLocks = Locks#{write := {WriteSeq+1,NewExpires}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {write, {handle,Path}, WriteSeq+1},
		    ?debugFmt("flock write final state ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};
		{unlocked,write} ->
                    if
                        Expires < Now ->
                            AfterExpiring = dict:store(Path,{Type,Locks#{read := {ReadSeq, 0, {0,0,0}}},DataOrChildren},State),
                            flock({handle,Path},LockType,Timeout,AfterExpiring);
                        true ->
                            ?debugFmt("ERROR flock write with existing read: ~p~n~p~n", [Path,State]),
                            {{error, already_read_locked},State}
                    end;
		{Expiration, _} ->
                    if
                        Expiration < Now ->
                            AfterExpiring = dict:store(Path,{Type,Locks#{write := {WriteSeq,unlocked}},DataOrChildren},State),
                            flock({handle,Path},LockType,Timeout,AfterExpiring);
                        true ->
                            ?debugFmt("ERROR flock with existing write: ~p~n~p~n", [Path,State]),
                            {{error, already_write_locked},State}
                    end
	    end
    end.

% Ignore the timeout and lock status and lock the file.
% The lock status can be checked with lockstatus(Handle,State)
forcelock({handle,Path},LockType,Timeout,State) ->
    Now = now(),
    case dict:find(Path,State) of
	error ->
	    {{error, file_or_dir_not_found},State};
	{ok, {Type, Locks, DataOrChildren}} ->
	    #{read := {ReadSeq,NumRead,Expires}, write := {WriteSeq,_}} = Locks,
            NewExpires = addseconds(Now,Timeout),
	    case LockType of
		read ->
                    NewExpiration = max(Expires,NewExpires),
                    NewSeq = if NumRead =:= 0 ->
                                     ReadSeq + 1;
                                true ->
                                     ReadSeq
                             end,
		    NewLocks = Locks#{read := {NewSeq,NumRead+1,NewExpiration}, write := {WriteSeq,unlocked}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {read, {handle,Path}, NewSeq},
		    ?debugFmt("forcelock read final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};		
		write ->
		    NewLocks = Locks#{read := {ReadSeq,0,{0,0,0}}, write := {WriteSeq+1,NewExpires}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {write, {handle,Path}, WriteSeq+1},
		    ?debugFmt("forcelock write final state ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState}
	    end
    end.

% Get the status of the lock
checktimeout({handle,Path},LockType,State) ->
    Now = now(),
    case dict:find(Path,State) of
	error ->
	    dontlock;
	{ok, {_, Locks, _}} ->
	    #{read := {_,NumRead,Expires}, write := {_,WriteStatus}} = Locks,
	    case {WriteStatus, LockType} of
		{unlocked,read} -> % no write lock, ok to acquire read lock
		    forcelock;
		{unlocked,write} when NumRead =:= 0 -> % no locks
		    forcelock;
		{unlocked,write} -> % requesting a write lock but there is a read lock so check expiration
		    if
                        Expires < Now ->
                            forcelock;
                        true ->
                            dontlock
                    end;
		{Expiration, _} -> % write locked, check the expiration
                    if
                        Expiration < Now ->
                            forcelock;
                        true ->
                            dontlock
			end
	    end
    end.

% Note that the lock was unsuccessful (due to check that occurred in the Master)
% This is here to make sure the client gets a reply and that this reply makes it into VR
dontlock({handle,Path}, State) ->
    case dict:find(Path,State) of
	error ->
	    {error, file_or_dir_not_found};
	{ok, {_, _, _}} ->
	    {error, already_locked}
    end.

% refreshes a lock (even if its expired)
refreshlock({handle,Path},Timeout,State) ->
    case dict:find(Path,State) of
	error ->
	    {{error, file_or_dir_not_found},State};
	{ok, {Type, Locks, DataOrChildren}} ->
	    #{read := {ReadSeq,NumRead,Expiration}, write := {WriteSeq,WriteStatus}} = Locks,
	    case WriteStatus of
		unlocked when NumRead > 0 ->
		    %% Read locked
		    NewLocks = Locks#{read := {ReadSeq,NumRead,max(Expiration,addseconds(now(),Timeout))}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {read, {handle,Path}, ReadSeq},
		    ?debugFmt("refresh final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};
		unlocked ->
		    ?debugFmt("ERROR refresh not locked: ~p~n~p~n", [Path,State]),
		    {{error, file_or_dir_not_locked},State};
		Expires ->
		    NewLocks = Locks#{write := {WriteSeq,max(Expires,addseconds(now(),Timeout))}},
                    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {write, {handle,Path}, WriteSeq},
		    ?debugFmt("refresh final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState}
	    end
    end.        

funlock({handle,Path},State) ->
    case dict:find(Path,State) of
	error ->
	    {{error, file_or_dir_not_found},State};
	{ok, {Type, Locks, DataOrChildren}} ->
	    #{read := {ReadSeq,NumRead,Expiration}, write := {WriteSeq,WriteStatus}} = Locks,
	    case WriteStatus of
		unlocked when NumRead > 0 ->
		    %% Read locked
		    NewLocks = Locks#{read := {ReadSeq,NumRead-1,Expiration}},
		    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {read, {handle,Path}, ReadSeq},
		    ?debugFmt("funlock final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState};
		unlocked ->
		    ?debugFmt("ERROR funlock not locked: ~p~n~p~n", [Path,State]),
		    {{error, file_or_dir_not_locked},State};
		_Expires ->
		    NewLocks = Locks#{write := {WriteSeq,unlocked}},
                    NewState = dict:store(Path,{Type,NewLocks,DataOrChildren},State),
		    Sequencer = {write, {handle,Path}, WriteSeq},
		    ?debugFmt("funlock final state: ~p~n~p~n", [Path,NewState]),
		    {{ok, Sequencer}, NewState}
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
	    ?debugFmt("remove final state: ~p ~p~n~p~n", [ok,Path,NewNewState]),
	    {{ok,removed},NewNewState};
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
		    {{ok,removed},NewNewState};
		_ ->
		    ?debugFmt("ERROR nonempty dir: ~p~n~p~n", [Path,State]),
		    {{error, cannot_remove_nonempty_dir},State}
	    end
    end.
		    
