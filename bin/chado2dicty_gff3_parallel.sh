#!/bin/bash

CMD="perl -Ilib ${PWD}/bin/modware-export chado2dictygff3" 
runcmd () {
    $CMD -o ${PWD}/data/discoideum/chr${1}.gff3 \
           -c ${PWD}/config/dicty_gff3.yaml --reference_id $1
}


counter=1
maxjob=3
names=(1 2 3 4 5 6 BF 2F 3F M R)
for entry in "${names[@]}"
do
	echo dumping chromosome $entry
  (runcmd $entry) &
  let "counter++"
  while [ $counter -gt $maxjob ]
  do
  	echo waiting for job to be done
  	wait
  	counter=1
  done
done

echo waiting for last batch of job
wait

echo all dumpings are finished
