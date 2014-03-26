#!/bin/sh

echoerr() { echo "$@" 1>&2; }

# executable portion

N=$2

if [ "$1" = "primary" ]; then
    echo "Killing primary is unimplemented"
    exit 1;
else
    # i=`expr $RANDOM % $N + 1`
    i=1
    echo "$i" >> stoppednodes
    echo "about to kill n${i}@localhost"
    # erl -sname "controller@localhost" -eval "rpc:block_call(n${i}@localhost,phat,stop,[])"
    TEMPFILE=$(mktemp /tmp/phat_escript.XXXXX)
    if [ 0 -ne $? ]; then
        echoerr "Could not create a temporary file, cannot complete"
        exit 1
    fi
    cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname connector@localhost
main (_) ->
  rpc:block_call(n${i}@localhost,phat,stop,[]).
EOF
    escript $TEMPFILE
    rm -f $TEMPFILE
    echo "done"
fi
