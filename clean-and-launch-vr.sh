N=$1

[ "$#" -eq 1 ] || die "1 arguments required, $# provided. Valid invocation:

  bash clean-and-launch-raid.sh N C

  - N -- the total number of nodes
"

rm -r tests
mkdir tests
killall beam.smp
erlc *.erl
bash start-raid.sh $N 1 tests
NODE_LIST+="["
for j in $(seq 1 $(expr $N - 1))
do
    NODE_LIST+="n$j@localhost, "
done
NODE_LIST+="n$N@localhost]"

echo erl -sname foo@localhost -eval "client:start_link($NODE_LIST)"
erl -sname foo@localhost -eval "client:start_link($NODE_LIST)"

