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
	App::cpanminus App::local::lib::helper

echo " ----------------------------------------------------------------------- "
echo "      List of recommended module for dependency management               "
echo "               App::cpanoutdated                                         "
echo "               App::pmuninstall                                          "
echo "               Devel::loaded                                             "
echo "               Dist::Zilla                                               "
echo "      Install them with cpanm <module name>                              "
echo " ----------------------------------------------------------------------- "

$folder/bin/localenv $SHELL
