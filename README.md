erlang-phat
===========

Erlang Modules:
 * `vr.erl`: View-state replication
 * `fs.erl`: Filesystem core
 * `server.erl`: The Phat app server wrapper


Testing 
-------

To test the VR module:

    $ erl
    > c(vr).
    > vr:test(local).

`testfs.erl`  contains the filesystem tests.   

