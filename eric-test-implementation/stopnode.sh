#!/bin/bash

# arguments

I=$1

# functions

echoerr() { echo "$@" 1>&2; }

# executable portion

TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXX)
if [ 0 -ne $? ]; then
    echoerr "Could not create a temporary file, cannot complete"
    exit 1
fi
cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname connector_stopnode_${RANDOM}@localhost
main (_) ->
  rpc:block_call(n${I}@localhost,phat,stop,[]).
EOF
escript $TEMPFILE
rm -f $TEMPFILE
