#!/bin/bash

function echoerr() { echo "$@" 1>&2; }
function die() { echo "$@" 1>&2 ; exit 1; }

# arguments

TYPE=$1
N=$2
WORKAREA=$3
SEED=$4

[ "$#" -eq 4 ] || die "4 arguments required, $# provided. Valid invocation:

  bash stopnode.sh type N workarea seed

  - type -- the type of node to revive
  - N -- the number of nodes in the Phat cluster
  - workarea -- a directory in which to place temporary files for testing
  - seed -- the random seed for this file
"


if [ -n $SEED ]; then
    RANDOM=$SEED
fi

# executable portion

if [ "$TYPE" = "primary" ]; then
    echo "Killing primary is unimplemented"
    exit 1;
else
    R=$RANDOM
    i=`expr $R % $N + 1`
    echo "$i" >> $WORKAREA/stoppednodes
    TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXX)
    if [ 0 -ne $? ]; then
        echoerr "Could not create a temporary file, cannot complete"
        exit 1
    fi
    cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname connector${RANDOM}@localhost
main (_) ->
  rpc:block_call(n${i}@localhost,phat,stop,[]).
EOF
    escript $TEMPFILE
    echo "killed n${i}@localhost"
    rm -f $TEMPFILE
fi
