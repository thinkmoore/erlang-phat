#!/bin/sh
# timed blocks

# arguments

N=$1
IMPL=$2

# functions

function timer_total() {
    for i in `seq 1 50` # repeat 100
    do
        sh ${IMPL}/stopnode.sh replica $N
        for i in `seq 1 10` # repeat 10
        do
            sh ${IMPL}/do.sh createfile 15 $N
        done
        sh ${IMPL}/revivenode.sh $N
    done
}

# executable portion

sh ${IMPL}/initialize.sh
sh ${IMPL}/startnodes.sh $N
time timer_total

