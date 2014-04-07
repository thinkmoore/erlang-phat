#!/bin/sh

# arguments

COMMAND=$1
#COUNT=$2 # unused
N=$3
WORKAREA=$4

# functions

echoerr() { echo "$@" 1>&2; }

# executable portion

TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXX)
if [ 0 -ne $? ]; then
    echoerr "Could not create a temporary file, cannot complete"
    exit 1
fi

# begin possible commands

if [ "$COMMAND" = "createfile" ]; then
    VR_FILE=`echo $TEMPFILE | sed 's:[/.]:_:g'`
    GUESS_MASTER=`expr $RANDOM % $N + 1`
    echo "createfile $VR_FILE" >> $WORKAREA/do-log
    echo "$VR_FILE" > $WORKAREA/reference-filesystem/$VR_FILE
    echo "client:call({mkfile, {handle,[]}, [file$VR_FILE], \"$VR_FILE\"})"
    cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname client_$VR_FILE@localhost
main (_) ->
  client:start_link(n${GUESS_MASTER}@localhost),
  client:call({mkfile, {handle,[]}, [file$VR_FILE], "$VR_FILE" }).
EOF
fi

# end possible commands

escript $TEMPFILE >> $WORKAREA/command-logs
rm -f $TEMPFILE
