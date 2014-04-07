#!/bin/sh
# timed blocks

# arguments

N=$1
IMPL=$2
WORKAREA=$3

# functions

function timer_total() {
    for i in `seq 1 2` # repeat 100
    do
        sh ${IMPL}/stopnode.sh replica $N $WORKAREA
        for i in `seq 1 10` # repeat 10
        do
            for i in `seq 1 5` # do 5 in parallel
            do
                sh ${IMPL}/do.sh createfile 15 $N $WORKAREA &
            done
        done
        sh ${IMPL}/revivenode.sh $N $WORKAREA
    done
}

# executable portion

sh ${IMPL}/initialize.sh $WORKAREA
sh ${IMPL}/startnodes.sh $N $WORKAREA
time timer_total

sh ${IMPL}/verify.sh $N $WORKAREA
