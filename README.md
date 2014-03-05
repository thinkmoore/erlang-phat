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
