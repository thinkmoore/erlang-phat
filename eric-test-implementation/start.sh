#!/bin/bash

function echoerr() { echo "$@" 1>&2; }
function die() { echo "$@" 1>&2 ; exit 1; }

# arguments

N=$1
WORKAREA=$2

[ "$#" -eq 2 ] || die "2 arguments required, $# provided. Valid invocation:

  bash startnodes.sh N workarea

  - N -- the number of nodes in the Phat cluster
  - workarea -- a directory in which to place temporary files for testing
"

# executable portion

# start the master and slaves
for i in `seq 1 $N`;
do
    rm -rf $WORKAREA/pipes$i
    rm -rf $WORKAREA/logs$i
    mkdir $WORKAREA/pipes$i
    mkdir $WORKAREA/logs$i
    echo "starting n${i}@localhost"
    run_erl -daemon $WORKAREA/pipes$i/ $WORKAREA/logs$i "erl -sname n${i}@localhost" &
done

echo "initializing the cluster"
# this guy just tells everyone to turn on and acts as a central log server, if
# he dies the cluster should be unaffected (aside from maybe broken pipes?).
rm -rf $WORKAREA/logs0
rm -rf $WORKAREA/pipes0
mkdir $WORKAREA/logs0
mkdir $WORKAREA/pipes0
run_erl -daemon $WORKAREA/pipes0/ $WORKAREA/logs0 "erl -sname n0@localhost -eval \"initialize_phat:init($N)\""

sleep `expr $N / 2`

# to kill the processes after you are done use
# killall beam.smp
