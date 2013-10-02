package Modware::Loader;

1;

__END__

=head1 NAME

Modware::Loader -  Command line apps for Chado relational database 

L<Chado|http://gmod.org/wiki/Introduction_to_Chado> is an open-source modular database
schema for biological data. This distribution provides L<MooseX::App::Cmd> based command
line applications to import and export biological data from Chado database.


=head1 INSTALLATION

You need to install 2/3 dependencies from B<github>, rest of them would be pulled from B<CPAN> as needed.
Install using B<cpanm> is highly recommended.
Use a latest version of L<cpanm|https://metacpan.org/module/cpanm>, at least 1.6 is needed.

=head2 Latest release 

=over

   cpanm -n  git://github.com/dictyBase/BioPortal-WebService.git
   cpanm -n  git://github.com/dictyBase/Modware-Loader.git

=back

If you install without (-n/notest flag) then install B<Test::Chado> before you install B<BioPortal-Webservice>.


=over

  cpanm git://github.com/dictyBase/Test-Chado.git

=back


=head2 Any particular release

Download the respective tarballs from their release pages in github and invoke B<cpanm> on them locally.

=over

=item

BioPortal-WebService L<release page|https://github.com/dictyBase/BioPortal-WebService/releases>

=item

Test-Chado L<release page|https://github.com/dictyBase/Test-Chado/releases>

=item

Modware-Loader L<release pages|https://github.com/dictyBase/Modware:Loader/releases>

=back


=head3 Using Build.PL,  cpan and friends

Just follow the instuctions in the B<INSTALL> file.


=head1 Quick start

Run any one of the following command

=over

=item modware-export

=item modware-load

=item modware-transform

=item modware-update

=back

Then follow the instructions to run any of the subcommand. Invoking the subcommand will display further help which is more or less self-explanatory.


=head1 Documentation/Examples

=over

=item L<Exporting annotations|http://dictybase.github.io/blog/2013/03/06/exporting-discoideum-annotations/>

=item L<Converting  tblastn alignments to GFF3 format|http://dictybase.github.io/refining-tblastn-protein-alignments/index.html>

=back
