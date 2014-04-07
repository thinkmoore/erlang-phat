#!/bin/sh

# arguments

COMMAND=$1
#COUNT=$2 # unused
N=$3
WORKAREA=$4
SEED=$5

# functions

echoerr() { echo "$@" 1>&2; }

# executable portion
if [ -n $SEED ]; then
    RANDOM=$SEED
fi

TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXX)
if [ 0 -ne $? ]; then
    echoerr "Could not create a temporary file, cannot complete"
    exit 1
fi

# begin possible commands

if [ "$COMMAND" = "createfile" ]; then
    VR_FILE=`echo $TEMPFILE | sed 's:[/.]:_:g'`
    # loop over the possible nodes trying to guess the master
    NOT_YET_DEAD_NODE=1
    while [[ ( $NOT_YET_DEAD_NODE -le $N ) && \
        `grep -q '^$NOT_YET_DEAD_NODE$' $WORKAREA/stoppednodes` -ne 0 ]]
    do
        NOT_YET_DEAD_NODE=`expr $NOT_YET_DEAD_NODE + 1`
    done
    cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname client_$VR_FILE@localhost
main (_) ->
  client:start_link([n${NOT_YET_DEAD_NODE}@localhost]),
  client:call({mkfile, {handle,[]}, [file$VR_FILE], "$VR_FILE" }).
EOF
    escript $TEMPFILE >> $WORKAREA/command-logs
    echo "createfile $VR_FILE" >> $WORKAREA/do-log
    echo "$VR_FILE" > $WORKAREA/reference-filesystem/$VR_FILE
    echo "client:call({mkfile, {handle,[]}, [file$VR_FILE], \"$VR_FILE\"})"
fi

# end possible commands

rm -f $TEMPFILE
