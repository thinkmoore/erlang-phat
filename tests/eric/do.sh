#!/bin/bash

# arguments

COMMAND=$1
TARGET=$2
FILENAME=$3
CONTENTS=$4
WORKAREA=$5

# functions

echoerr() { echo "$@" 1>&2; }

# exectuable

TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXX)
if [ 0 -ne $? ]; then
    echoerr "Could not create a temporary file, cannot complete"
    exit 1
fi

if [ "$COMMAND" = "createfile" ]; then
    echo "client:start_link([n${TARGET}@localhost])"
    cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname client_${FILENAME}@localhost
main (_) ->
  client:start_link([n${TARGET}@localhost]),
  RESULT=client:call({mkfile, {handle,[]}, [$FILENAME], "$CONTENTS" }),
  io:fwrite("Result was ~p~n", [RESULT]).
EOF
    escript $TEMPFILE >> $WORKAREA/command-logs
    echo "client:call({mkfile, {handle,[]}, [$FILENAME], \"$CONTENTS\"})"
    EXIT_VALUE=$?
    rm -f $TEMPFILE
    exit $EXIT_VALUE
fi

