package Modware::Loader;

1;

__END__

=head1 NAME

Modware::Loader -  Command line apps for Chado relational database 

L<Chado|http://gmod.org/wiki/Introduction_to_Chado> is an open-source modular database
schema for biological data. This distribution provides L<MooseX::App::Cmd> based command
line applications to import and export biological data from Chado database.


=head1 INSTALLATION

=head2 Using cpanm

Use a latest version of L<cpanm|https://metacpan.org/module/cpanm>, at least 1.6 is needed.
You need to install 2/3 dependencies from B<github>, rest of them would be pulled from B<CPAN> as needed.

=over

   cpanm -n  git://github.com/dictyBase/Modware-Loader.git

=back

If you install without (-n/notest flag) then add B<Test::Chado>


=over

  cpanm git://github.com/dictyBase/Test-Chado.git

=back


=head2 Manually

Download the Modware-Loader tarballs from github master and invoke B<cpanm> on them.

=over

=item

Test-Chado L<tarball|https://github.com/dictyBase/Test-Chado/archive/master.tar.gz>

=item

Modware-Loader L<tarball|https://github.com/dictyBase/Modware:Loader/archive/master.tar.gz>

=back


=head3 Using Build.PL,  cpan and friends

Just follow the instuctions in the B<INSTALL> file.

=head3 Directly from the git repository

This is primarilly intended for authors/developers.

=over

    git checkout git://github.com/dictyBase/Modware-Loader.git
    cpanm -n Dist::Zilla
    dzil listdeps --author --missing | cpanm -n
    dzil install

=back

=head1 Build Status

=begin HTML

<a href='https://travis-ci.org/dictyBase/Modware-Loader'>
  	<img src='https://travis-ci.org/dictyBase/Modware-Loader.png?branch=develop' alt='Travis CI status'/>
</a>

<a href='https://coveralls.io/r/dictyBase/Modware-Loader'>
	<img src='https://coveralls.io/repos/dictyBase/Modware-Loader/badge.png?branch=develop' alt='Coverage Status' />
</a>

=end HTML
