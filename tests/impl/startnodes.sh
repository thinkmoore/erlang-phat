# start the master and slaves
for i in `seq 1 $1`;
do
    rm -rf pipes$i
    rm -rf logs$i
    mkdir pipes$i
    mkdir logs$i
    echo "starting n${i}@localhost"
    run_erl -daemon pipes$i/ logs$i "erl -sname n${i}@localhost" &
done

echo "initializing the cluster"
# this guy just tells everyone to turn on and acts as a central log server, if
# he dies the cluster should be unaffected (aside from maybe broken pipes?).
rm -rf logs0
rm -rf pipes0
mkdir logs0
mkdir pipes0
run_erl -daemon pipes0/ logs0 "erl -sname n0@localhost -eval \"initialize_phat:init($1)\""

sleep 1

# to kill the processes after you are done use
# killall beam.smp
