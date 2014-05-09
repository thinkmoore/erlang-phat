rm -r tests
mkdir tests
killall beam.smp
erlc *.erl
eric-test-implementation/start.sh 3 tests
erl -sname foo@localhost -eval "client:start_link([n1@localhost,n2@localhost,n3@localhost])"
