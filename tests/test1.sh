#!/bin/bash
# timed blocks

# arguments

N=$1
IMPL=$2
WORKAREA=$3

DO_IMPL='bash /Users/danking/projects/erlang-phat/tests/eric/do.sh'

# functions

function timer_total() {
    for i in `seq 1 2` # repeat 100
    do
        bash ${IMPL}/stopnode.sh replica $N $WORKAREA $RANDOM
        for i in `seq 1 10` # repeat 10
        do
            bash ${IMPL}/do.sh createfile 15 $N $WORKAREA $RANDOM "$DO_IMPL"
        done
        bash ${IMPL}/revivenode.sh $N $WORKAREA $RANDOM
    done
}

# executable portion

bash ${IMPL}/initialize.sh $WORKAREA
bash ${IMPL}/startnodes.sh $N $WORKAREA

sleep 5 # wait for the nodes to initialize

time timer_total

bash ${IMPL}/verify.sh $N $WORKAREA
