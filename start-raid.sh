#!/bin/bash

function echoerr() { echo "$@" 1>&2; }
function die() { echo "$@" 1>&2 ; exit 1; }

# arguments

N=$1
C=$2
WORKAREA=$3

[ "$#" -eq 3 ] || die "3 arguments required, $# provided. Valid invocation:

  bash startnodes.sh N workarea

  - N -- the total number of nodes
  - C -- the number of phat groups
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

function initcluster() {
    START=$1
    COUNT=$2

    echo "initializing a phat cluster of size $COUNT starting at $START"
# this guy just tells everyone to turn on and acts as a central log server, if
# he dies the cluster should be unaffected (aside from maybe broken pipes?).
    rm -rf $WORKAREA/logs-cluster$START
    rm -rf $WORKAREA/pipes-cluster$START
    mkdir $WORKAREA/logs-cluster$START
    mkdir $WORKAREA/pipes-cluster$START
    run_erl -daemon $WORKAREA/pipes-cluster$START/ $WORKAREA/logs-cluster$START "erl -sname c$START@localhost -eval \"initialize_phat:init_count($START,$COUNT)\""

    sleep `expr $COUNT / 2`
}

START=1
COUNT=`expr $N / $C`
for i in `seq 1 $C`;
do
    initcluster $START $COUNT
    START=`expr $START + $COUNT`;
done

# to kill the processes after you are done use
# killall beam.smp
