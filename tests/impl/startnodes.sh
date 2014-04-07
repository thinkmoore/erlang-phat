N=$1
WORKAREA=$2
SEED=$3

if [ -n $SEED ]; then
    RANDOM=$SEED
fi

# start the master and slaves
for i in `seq 1 $N`;
do
    rm -rf $WORKAREA/pipes$i
    rm -rf $WORKAREA/logs$i
    mkdir $WORKAREA/pipes$i
    mkdir $WORKAREA/logs$i
    echo "starting n${i}@localhost"
    run_erl -daemon $WORKAREA/pipes$i/ $WORKAREA/logs$i "erl -sname n${i}@localhost" &
done

echo "initializing the cluster"
# this guy just tells everyone to turn on and acts as a central log server, if
# he dies the cluster should be unaffected (aside from maybe broken pipes?).
rm -rf $WORKAREA/logs0
rm -rf $WORKAREA/pipes0
mkdir $WORKAREA/logs0
mkdir $WORKAREA/pipes0
run_erl -daemon $WORKAREA/pipes0/ $WORKAREA/logs0 "erl -sname n0@localhost -eval \"initialize_phat:init($N)\""

sleep 1

# to kill the processes after you are done use
# killall beam.smp
