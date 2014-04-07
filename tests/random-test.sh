#!/bin/sh
# arguments

N=$1
SEED=$2
RUNS=$3
IMPL=$4
WORKAREA=$5
VERIFYLOG=$6

# functions

# timed blocks

function timer_total() {
    # $RANDOM generates numbers in [0, 32767]
    for i in `seq 1 $RUNS`
    do
        R=$RANDOM
        CHILD_SEED=$RANDOM
        if [ $R -le 10000 ];
        then
            sh ${IMPL}/do.sh createfile 5 $N $WORKAREA $CHILD_SEED &
        elif [ $R -le 15000 ];
        then
            sh ${IMPL}/stopnode.sh replica $N $WORKAREA $CHILD_SEED &
        elif [ $R -le 20000 -a -s $WORKAREA/stoppednodes ];
        then
            sh ${IMPL}/revivenode.sh $N $WORKAREA $SEED &
        else
            sh ${IMPL}/do.sh createfile 10 $N $WORKAREA $CHILD_SEED &
        fi
    done
}

# executable portion

RANDOM=$SEED

sh ${IMPL}/initialize.sh $WORKAREA
sh ${IMPL}/startnodes.sh $N $WORKAREA
time timer_total

sleep 1
echo "Verification..."

if [ -z $VERIFYLOG ]; then
    sh ${IMPL}/verify.sh $N $WORKAREA
else
    sh ${IMPL}/verify.sh $N $WORKAREA > $VERIFYLOG
fi
