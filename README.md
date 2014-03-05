erlang-phat
===========

Erlang Modules:
 * `vr.erl`: View-state replication
 * `fs.erl`: Filesystem core
 * `server.erl`: The Phat app server wrapper
 * `phat.erl`: The Phat supervisor, manages the above modules


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
    $ ...

Then on each node (starting with the master), start Phat:

    > phat:start_link([n1@localhost,n2@localhost,...]).
    
Then you can play around:

    > phat:test().
    > Response = server:clientRequest(0,{getroot}).
    
You can induce various types of failures using the `phat` module.
`phat:inject_fault/1` takes as an argument a module to inject a fault into
on the current node (one of `fs`, `ps`, or `vr`). All other modules are brought
down and Phat is restarted in a clean state on the node (This doesn't play nice
with vr currently...). `phat:stop/0` shuts down Phat on a node. `phat:restart/0`
should restart Phat on a node.
