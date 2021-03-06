#!/bin/bash

# arguments

TARGET=$1
FILENAME=$2
CONTENTS=$3

# functions

echoerr() { echo "$@" 1>&2; }

# executable

TEMPFILE=$(mktemp /tmp/phat_escript.XXXXXXX)
cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname verify_${RANDOM}@localhost -hidden
main (_) ->
  client:start_link([n${TARGET}@localhost]),
  PhatContents = client:call({getcontents, {handle,[$FILENAME]}}),
  ActualContents = "$CONTENTS",
  case PhatContents of
     {error,file_not_found} ->
        io:format("File $FILENAME was not created in the Phat file system!~n"),
        halt(2);
     {unexpected,_} ->
        io:format("I have no idea what happened: ~p", [PhatContents]),
        halt(3);
     _ ->
        case string:equal(ActualContents, PhatContents) of
           true ->
              halt(0);
           false ->
              io:format("Phat value, ~p, differs from actual value, ~p.~n",
                        [PhatContents, ActualContents]),
              halt(1)
        end
  end.

EOF
escript $TEMPFILE </dev/null
ERR=$?
rm -f $TEMPFILE
exit $ERR
