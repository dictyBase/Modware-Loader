#!/bin/sh

perl=$(which perl)

if [ -z $1 ]
	then
		folder=$PWD/locallib/$($perl -e 'print $^V')
		if [ ! -d $folder ]
			then
				mkdir -p $folder
		fi
fi

echo " ------------------------------------------------------------------"
echo "    going to install App::cpanminus and App::local::lib::helper    "
echo "    in $folder for local-lib                                       "
echo " ------------------------------------------------------------------"

curl -L http://cpanmin.us | $perl - -L $folder \
	App::cpanminus local::lib

echo " ----------------------------------------------------------------------- "
echo "      List of recommended module for dependency management               "
echo "               App::cpanoutdated                                         "
echo "               App::pmuninstall                                          "
echo "               Devel::loaded                                             "
echo "      Install them with cpanm <module name>                              "
echo " ----------------------------------------------------------------------- "

ETC=$folder/etc
if [ ! -d $ETC ]
	then
		mkdir -p $ETC
fi	

LLIB=$folder/lib/perl5
LLIBFILE=$ETC/locallibrc
LIBEXPORT=$($perl -I$LLIB -Mlocal::lib=$folder)
echo $LIBEXPORT > $LLIBFILE


echo " ------------------------------------------------------------ "
echo "                   IMPORTANT                                  "
echo "                   *********                                  "
echo "                Run source $LLIBFILE                          "
echo "                or      .  $LLIBFILE                          "
echo "           to activate local lib environment                  "
echo "                                                              "
echo "     Then Install dependencies with cpanm <module name>       "
echo " ------------------------------------------------------------ "
