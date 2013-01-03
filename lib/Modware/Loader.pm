package Modware::Loader;

1;

__END__

=head1 NAME

Modware::Loader -  Command line apps for Chado relational database 

L<http://gmod.org/wiki/Introduction_to_Chado|Chado> is an open-source modular database
schema for biological data. This distribution provides L<MooseX::App::Cmd> based command
line applications to import and export biological data from Chado database.


=head1 INSTALLATION

=head2 Using cpanm

=over

=item  

Download a distribution tarball either from a git B<tag> or from <build/develop> branch.

=item

cpanm <tarball>

=back

=head2 Using Build.PL,  cpan and friends

Download the disribution tarball and follow the instruction in the included B<INSTALL> file.


=head2 From the git repository

This is primarilly intended for authors/developers.

=over

=item

git checkout git://github.com/dictyBase/Modware-Loader.git

=item

Install L<Dist::Zilla> 
  
cpanm -n Dist::Zilla

=item

dzil listdeps --author --missing | cpanm -n

dzil install

=back 

