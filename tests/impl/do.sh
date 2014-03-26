#!/bin/sh

echoerr() { echo "$@" 1>&2; }

# executable portion

TEMPFILE=$(mktemp /tmp/phat_escript.XXXXX)
if [ 0 -ne $? ]; then
    echoerr "Could not create a temporary file, cannot complete"
    exit 1
fi

# begin possible commands

if [ "$1" = "createfile" ]; then
    VR_FILE=`echo $TEMPFILE | sed 's:[/.]:_:g'`
    cat > $TEMPFILE <<EOF
#!/usr/bin/env escript
%%! -sname client_$VR_FILE@localhost
main (_) ->
  client:start_link(n1@localhost),
  client:call({mkfile, {handle,[]}, [file$VR_FILE], "$VR_FILE" }).
EOF
fi

# end possible commands

escript $TEMPFILE
rm -f $TEMPFILE
