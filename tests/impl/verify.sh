#!/bin/bash

# arguments

N=$1
WORKAREA=$2

# functions

echoerr() { echo "$@" 1>&2; }

# executable portion

while read line
do
    echo "verifying $line"
    if [[ "$line" =~ createfile\ (.*) ]]; then
        CONTENTS=$(cat $WORKAREA/reference-filesystem/${BASH_REMATCH[1]})
        VR_FILE=file${CONTENTS}
        TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXX)
        # loop over the possible nodes trying to guess the master
        MASTER_GUESS=0
        RESULT=255
        while [ $MASTER_GUESS -le $N -a $RESULT -ne 0 ]
        do
            cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname verify_${RANDOM}@localhost
main (_) ->
  client:start_link(n${MASTER_GUESS}@localhost),
  PhatContents = client:call({getcontents, {handle,[$VR_FILE]}}),
  ActualContents = "$CONTENTS",
  case PhatContents of
     {error,file_not_found} ->
        io:format("File $VR_FILE was not created in the Phat file system!~n"),
        halt(2);
     _ ->
        case string:equal(ActualContents, PhatContents) of
           true ->
              halt(0);
           false ->
              io:format("Phat value, ~s, differs from actual value, ~s.~n",
                        [PhatContents, ActualContents]),
              halt(1)
        end
  end.

EOF
            escript $TEMPFILE </dev/null
            RESULT=$?
            MASTER_GUESS=`expr $MASTER_GUESS + 1`
        done
    fi
done < $WORKAREA/do-log


