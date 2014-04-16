#!/bin/sh

function die() { echo "$@" 1>&2 ; exit 1; }
function echoerr() { echo "$@" 1>&2; }

# arguments

COMMAND=$1
#COUNT=$2 # unused
N=$3
WORKAREA=$4
SEED=$5

[ "$#" -eq 5 ] || die "5 arguments required, $# provided. Valid invocation:

  bash do.sh command_name count N workarea seed

  - command_name -- the file system command to run
  - count -- the number of times to run, in parallel, the command
  - N -- the number of nodes in the Phat cluster
  - workarea -- a directory in which to place temporary files for testing
  - seed -- the $RANDOM seed for this file
"

# functions


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
    grep -q "^${NOT_YET_DEAD_NODE}\$" $WORKAREA/stoppednodes
    RESULT=$?
    while [[ $NOT_YET_DEAD_NODE -lt $N && $RESULT -eq 0 ]]
    do
        grep -q "^${NOT_YET_DEAD_NODE}\$" $WORKAREA/stoppednodes
        RESULT=$?
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
    EXITCODE=$?
    echo "createfile $VR_FILE" >> $WORKAREA/do-log
    echo "$VR_FILE" > $WORKAREA/reference-filesystem/$VR_FILE
    echo "client:call({mkfile, {handle,[]}, [file$VR_FILE], \"$VR_FILE\"})"
    if [ $EXITCODE -ne 0 ]
    then
        echo "  previous call failed, exit code was $EXITCODE"
        echo "  tried talking to n${NOT_YET_DEAD_NODE}@localhost"
    fi
fi

# end possible commands

rm -f $TEMPFILE
