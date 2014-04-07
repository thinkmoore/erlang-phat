#!/bin/bash
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
            bash ${IMPL}/do.sh createfile 5 $N $WORKAREA $CHILD_SEED &
        elif [ $R -le 15000 -a "`wc -l $WORKAREA/stoppednodes | awk {'print $1'}`" -le $F ];
        then
            bash ${IMPL}/stopnode.sh replica $N $WORKAREA $CHILD_SEED &
        elif [ $R -le 20000 -a -s $WORKAREA/stoppednodes ];
        then
            bash ${IMPL}/revivenode.sh $N $WORKAREA $SEED &
        else
            bash ${IMPL}/do.sh createfile 10 $N $WORKAREA $CHILD_SEED &
        fi
    done
}

# executable portion

RANDOM=$SEED

bash ${IMPL}/initialize.sh $WORKAREA
bash ${IMPL}/startnodes.sh $N $WORKAREA
time timer_total

sleep 10
echo "Verification..."

if [ -z $VERIFYLOG ]; then
    bash ${IMPL}/verify.sh $N $WORKAREA
else
    bash ${IMPL}/verify.sh $N $WORKAREA > $VERIFYLOG
fi
