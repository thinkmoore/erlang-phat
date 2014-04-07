#!/bin/bash

echoerr() { echo "$@" 1>&2; }

# arguments

TYPE=$1
N=$2
WORKAREA=$3
SEED=$4

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
    echo "about to kill n${i}@localhost"
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
    rm -f $TEMPFILE
fi
