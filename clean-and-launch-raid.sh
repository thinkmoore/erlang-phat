N=$1
C=$2

[ "$#" -eq 2 ] || die "2 arguments required, $# provided. Valid invocation:

  bash clean-and-launch-raid.sh N C

  - N -- the total number of nodes
  - C -- the number of pnhat groups
"

rm -r tests
mkdir tests
killall beam.smp
erlc *.erl
bash start-raid.sh $N $C tests
NODE_PER_CLUSTER=$(expr $N / $C)
NODE_LIST="["
for i in $(seq 1 $NODE_PER_CLUSTER $(expr $N - $NODE_PER_CLUSTER))
do
    NODE_LIST+="["
    for j in $(seq $i $(expr $i + $NODE_PER_CLUSTER - 2))
    do
        NODE_LIST+="n$j@localhost, "
    done
    NODE_LIST+="n$(expr $j + 1)@localhost],"
done
NODE_LIST+="["
for j in $(seq $(expr $N - $NODE_PER_CLUSTER + 1) $(expr $N - 1))
do
    NODE_LIST+="n$j@localhost, "
done
NODE_LIST+="n$N@localhost]]"

echo erl -sname foo@localhost -eval "raidclient:start_link($NODE_LIST)"
erl -sname foo@localhost -eval "raidclient:start_link($NODE_LIST)"

