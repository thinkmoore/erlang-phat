#!/bin/bash
# timed blocks

# arguments

N=$1
IMPL=$2
WORKAREA=$3

ERIC=/Users/danking/projects/erlang-phat/tests/eric

DO_IMPL="bash ${ERIC}/do.sh"
STOP_IMPL="bash ${ERIC}/stopnode.sh"
REVIVE_IMPL="bash ${ERIC}/revivenode.sh"
STARTNODES_IMPL="bash ${ERIC}/startnodes.sh"

# functions

function timer_total() {
    for i in `seq 1 2` # repeat 100
    do
        bash ${IMPL}/stopnode.sh replica $N $WORKAREA $RANDOM "$STOP_IMPL"
        for i in `seq 1 10` # repeat 10
        do
            bash ${IMPL}/do.sh createfile 15 $N $WORKAREA $RANDOM "$DO_IMPL"
        done
        bash ${IMPL}/revivenode.sh $N $WORKAREA $RANDOM "$REVIVE_IMPL"
    done
}

# executable portion

bash ${IMPL}/initialize.sh $WORKAREA
$STARTNODES_IMPL $N $WORKAREA

time timer_total

bash ${IMPL}/verify.sh $N $WORKAREA
