if [ -z $1 ]
	then
		folder=`pwd`/perl5
fi

if [ ! -d $folder ]
	then
		echo "$folder does not exist !!!! "
		echo "Please run sandbox/bootstrap.sh $folder ...."
		exit
fi


shell=$SHELL
$folder/bin/localenv $shell
