#!/bin/bash

# arguments

N=$1
WORKAREA=$2

# functions

echoerr() { echo "$@" 1>&2; }

# executable portion

FAILURES=0

while read line
do
    echo "verifying $line"
    if [[ "$line" =~ createfile\ (.*) ]]; then
        CONTENTS=$(cat $WORKAREA/reference-filesystem/${BASH_REMATCH[1]})
        VR_FILE=file${CONTENTS}
        TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXX)
        # loop over the possible nodes trying to guess the master
        NOT_YET_DEAD_NODE=1
        while [[ ( $NOT_YET_DEAD_NODE -le $N ) && \
            `grep -q '^$NOT_YET_DEAD_NODE$' $WORKAREA/stoppednodes` -ne 0 ]]
        do
            NOT_YET_DEAD_NODE=`expr $NOT_YET_DEAD_NODE + 1`
        done

        cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname verify_${RANDOM}@localhost
main (_) ->
  client:start_link(n${NOT_YET_DEAD_NODE}@localhost),
  PhatContents = client:call({getcontents, {handle,[$VR_FILE]}}),
  ActualContents = "$CONTENTS",
  case PhatContents of
     {error,file_not_found} ->
        io:format("File $VR_FILE was not created in the Phat file system!~n"),
        halt(2);
     {unexpected,_} ->
        io:format("I have no idea what happened: ~s", [PhatContents]),
        halt(3);
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

        if [ $? -ne 0 ]
        then
            FAILURES=`expr $FAILURES + 1`
        fi
    fi
done < $WORKAREA/do-log

echo "Verification found $FAILURES failures"
exit $FAILURES
