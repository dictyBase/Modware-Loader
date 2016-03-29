package Modware::Loader;

1;

__END__

=head1 NAME

Modware::Loader -  Command line apps for Chado relational database 

=head1 DESCRIPTION

L<Chado|http://gmod.org/wiki/Introduction_to_Chado> is an open-source modular database
schema for biological data. This distribution provides L<MooseX::App::Cmd> based command
line applications to import and export biological data from Chado database.


=head1 INSTALLATION

Install using B<cpanm> is highly recommended.
Use a latest version of L<cpanm|https://metacpan.org/module/cpanm>, at least 1.6 is needed.

=head2 Latest release 

=over

   cpanm -n  git://github.com/dictyBase/Modware-Loader.git

=back


=head2 Any particular release

Download the respective tarballs from their release pages in github and invoke B<cpanm> on them locally.

=over

=item

Modware-Loader L<release pages|https://github.com/dictyBase/Modware:Loader/releases>

=back

=head3 Using Build.PL,  cpan and friends

Just follow the instuctions in the B<INSTALL> file.

=head2 Using docker

Use any particular tag from L<docker hub|https://hub.docker.com/r/dictybase/modware-loader/tags>

    $_> docker run --rm dictybase/modware-loader:1.8 <cmd>


=head1 Build Status

=for HTML <a href="https://travis-ci.org/dictyBase/Modware-Loader"><img src="https://travis-ci.org/dictyBase/Modware-Loader.svg?branch=master"></a>

=head1 Documentation

Run any one of the following command

=over

=item modware-export

=item modware-load

=item modware-transform

=item modware-update

=back

Then follow the instructions to run any of the subcommand. Invoking the subcommand will display further help which is more or less self-explanatory.

=head2 Quick example

Run one of the command

      $_> modware-load 

        Available commands:

            commands: list the application's commands
                help: display a command's help screen

           adhocobo2chado:  Load an adhoc ontology in chado database 
                obo2chado:  Load ontology from obo flat file to chado database
         oboclosure2chado:  Populate cvtermpath in chado database
       bioportalobo2chado:  Load ontology from NCBO bioportal to chado database
           dictygaf2chado:  Load GO annotations from GAF file to chado database
        dropontofromchado:  Drop ontology from chado database (use sparingly)
                 gb2chado:  Populate oracle chado database from genbank file
         gbassembly2chado:  Load genome assembly from genbank to oracle chado database


Run one subcommand

      $_> modware-load obo2chado

        modware-load obo2chado [-?chilpu] [long options...]
           -i --input             Name of the obo file
           --dry_run              Dry run do not save anything in database
           -h -? --usage --help   Prints this usage information.
           --pg_schema            Name of postgresql schema where the ontology
                                  will be loaded, default is public, obviously
                                  ignored for other backend
           --sqllib               Path to sql library in INI format, by default
                                  picked up from the shared lib folder. Mostly a
                                  developer option.
           --attr --attribute     Additional database attribute
           --pass -p --password   database password


Execute the subcommand

      $_> modware-load obo2chado --dsn 'dbi:Pg:database=mychado'  -u tucker -p tucker -i go.obo

B<Done.>


=head2 Tutorials/Blog posts

=over

=item L<Exporting annotations|http://dictybase.github.io/blog/2013/03/06/exporting-discoideum-annotations/>

=item L<Converting  tblastn alignments to GFF3 format|http://dictybase.github.io/refining-tblastn-protein-alignments/index.html>

=item L<Design pattern of chado loader|http://dictybase.github.io/blog/2013/09/18/chado-loader-design>

=back

=head1 Automated release and docker build

This is only meant for developers. The automated process is done through `Makefile`. 

=head3 Prerequisites

=over

=item Docker

=item curl

=item L<jq|https://stedolan.github.io/jq/>

=item Github personal access L<token|https://github.com/blog/1509-personal-api-tokens> . Store it in `~/.github-release` file.

=back

Then bump the version in `dist.ini` file and run the command
    
    $_> make release && make gh-release

