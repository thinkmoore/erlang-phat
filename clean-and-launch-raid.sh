rm -r tests
mkdir tests
killall beam.smp
erlc *.erl
bash start-raid.sh 9 3 tests
erl -sname foo@localhost -eval "raidclient:start_link([[n1@localhost, n2@localhost, n3@locahost],[n4@localhost,n5@localhost,n6@localhost],[n7@localhost,n8@localhost,n9@localhost]])"
