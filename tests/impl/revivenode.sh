#!/bin/sh

echoerr() { echo "$@" 1>&2; }

# arguments

N=$1
WORKAREA=$2
SEED=$3

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
    echo "about to revive n${i}@localhost"
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
    rm -f $TEMPFILE
fi
