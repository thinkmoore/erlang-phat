Modules
-------

 * `vr.erl`: View-state replication
 * `fs.erl`: Filesystem core
 * `server.erl`: The Phat app server wrapper
 * `phat.erl`: The Phat supervisor, manages the above modules

Usage
-----

This code requires Erlang R17 due to the use of maps.

1. Compile the modules

        $ erlc *.erl
    
2. Start 3 nodes in separate shells:
    
        $ erl -sname n1@localhost
        > phat:start_link([n1@localhost,n2@localhost,n3@localhost]).

        $ erl -sname n2@localhost
        > net_adm:ping(n1@localhost).
        > phat:start_link([n1@localhost,n2@localhost,n3@localhost]).
        
        $ erl -sname n3@localhost
        > net_adm:ping(n1@localhost).
        > phat:start_link([n1@localhost,n2@localhost,n3@localhost]).
        
3. In a separate client shell, perform the following:
        
        $ erl -sname client@localhost
        > client:start_link(n1@localhost).
        > client:call({getroot}).

Testing 
-------

To test the VR module:

    $ erl
    > c(vr).
    > vr:test(local).

`testfs.erl`  contains the filesystem tests.

To test Phat as a whole, launch a few nodes:

    $ erl -sname n1@localhost
    $ erl -sname n2@localhost
    $ erl -sname n3@localhost

Then on each node (starting with the master), start the Phat server:

    > phat:start_link([n1@localhost,n2@localhost,n3@localhost]).
    
Then you can play around on the Phat server side:

    > phat:test().
    > Response = server:clientRequest(0,{getroot}).

You can induce various types of failures using the `phat` module.
`phat:inject_fault/1` takes as an argument a module to inject a fault into
on the current node (one of `fs`, `ps`, or `vr`). All other modules are brought
down and Phat is restarted in a clean state on the node (This doesn't play nice
with vr currently...). `phat:stop/0` shuts down Phat on a node. `phat:restart/0`
should restart Phat on a node.

Profiling RaidPhat
------------------

To test the performance of RaidPhat, there are two bash scripts to aid in 
automated testing:

 * `clean-and-launch-raid.sh N C`: Starts a RaidPhat cluster with `N` nodes 
    separated by `C` different clusters and drops you into the erlang command-line.
 * `clean-and-launch-vr.sh N`: Starts a RaidPhat cluster with `N` nodes in
    one cluster -- does not actually start a raidclient and instead gives you
    access to a single VR client.

In both the `client` and `raidclient` modules, there are `profile` and `multi_profile`
functions. `profile(Filesize, Trials)` profiles a single store and fetch on the 
PhatRaid cluster with a file with `Filesize` length, and repeats `Trials` times.
`multi_profile(Filesize, Trials)` is similar to `profile`, but performs the trials
all together and averages the overall time.

To adjust the disk performance, see the constants in `fs.erl`; specifically:

 * `-define(MB_PER_CHAR, 1)`: number of megabytes a character represents
 * `-define(DISK_WRITE_THRUPUT_MB_S, 55.0)`: sequential write speed of the drive
 * `-define(DISK_WRITE_ACCESS_TIME_S, 0.00032)`: write access time of the drive
 * `-define(DISK_READ_THRUPUT_MB_S, 208.0)`: sequential read speed of the drive
 * `-define(DISK_READ_ACCESS_TIME_S, 0.00022)`: read access time of the drive

Here is an example usage of the profiler:

    % bash clean-and-launch-raid.sh 9 3 
    starting n1@localhost
    starting n2@localhost
    starting n3@localhost
    starting n4@localhost
    starting n5@localhost
    starting n6@localhost
    starting n7@localhost
    starting n8@localhost
    starting n9@localhost
    initializing a phat cluster of size 3 starting at 1
    initializing a phat cluster of size 3 starting at 4
    initializing a phat cluster of size 3 starting at 7
    erl -sname foo@localhost -eval raidclient:start_link([[n1@localhost, n2@localhost, n3@localhost],[n4@localhost, n5@localhost, n6@localhost],[n7@localhost, n8@localhost, n9@localhost]])
    Erlang/OTP 17 [RELEASE CANDIDATE 2] [erts-6.0] [source-a74e66a] [64-bit] [smp:4:4] [async-threads:10] [hipe] [kernel-poll:false]

    Eshell V6.0  (abort with ^G)
    (foo@localhost)1> raidclient:multi_profile(100, 10).
    Trials: 10 Avg Store Time: 924.2782 ms -- Avg Fetch Time: 249.08620000000002 ms 
    ok
    (foo@localhost)2> 

