#!/bin/bash
# timed blocks

# arguments

N=$1
IMPL=$2
WORKAREA=$3

# functions

function timer_total() {
    for i in `seq 1 2` # repeat 100
    do
        bash ${IMPL}/stopnode.sh replica $N $WORKAREA
        for i in `seq 1 10` # repeat 10
        do
            for i in `seq 1 5` # do 5 in parallel
            do
                bash ${IMPL}/do.sh createfile 15 $N $WORKAREA &
            done
        done
        bash ${IMPL}/revivenode.sh $N $WORKAREA
    done
}

# executable portion

bash ${IMPL}/initialize.sh $WORKAREA
bash ${IMPL}/startnodes.sh $N $WORKAREA
time timer_total

bash ${IMPL}/verify.sh $N $WORKAREA
