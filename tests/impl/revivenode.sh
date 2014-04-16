#!/bin/bash

function echoerr() { echo "$@" 1>&2; }
function die() { echo "$@" 1>&2 ; exit 1; }

# arguments

N=$1
WORKAREA=$2
SEED=$3

[ "$#" -eq 3 ] || die "3 arguments required, $# provided. Valid invocation:

  bash do.sh N workarea seed

  - N -- the number of nodes in the Phat cluster
  - workarea -- a directory in which to place temporary files for testing
  - seed -- the random seed for this file
"

# executable portion
if [ -n $SEED ]; then
    RANDOM=$SEED
fi

read i <$WORKAREA/stoppednodes
# remove the above line from the file
sed -e '1,1d' -i.bak $WORKAREA/stoppednodes

if [ "$i" = "primary" ]; then
    echo "reviving primary is unimplemented"
    exit 1;
else
    TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXXX)
    if [ 0 -ne $? ]; then
        echoerr "Could not create a temporary file, cannot complete"
        exit 1
    fi
    cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname connector${RANDOM}@localhost
main (_) ->
  rpc:block_call(n${i}@localhost,phat,restart,[]).
EOF
    escript $TEMPFILE
    echo "revived n${i}@localhost"
    rm -f $TEMPFILE
fi
