#!/bin/sh

echoerr() { echo "$@" 1>&2; }

# executable portion

read i <stoppednodes
sed -e '1,1d' -i.bak stoppednodes

if [ "$i" = "primary" ]; then
    echo "reviving primary is unimplemented"
    exit 1;
else
    echo "about to revive n${i}@localhost"
    # erl -sname "controller@localhost" -eval "rpc:block_call(n${i}@localhost,phat,stop,[])"
    TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXX)
    if [ 0 -ne $? ]; then
        echoerr "Could not create a temporary file, cannot complete"
        exit 1
    fi
    cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname connector@localhost
main (_) ->
  rpc:block_call(n${i}@localhost,phat,restart,[]).
EOF
    escript $TEMPFILE
    rm -f $TEMPFILE
    echo "done"
fi
