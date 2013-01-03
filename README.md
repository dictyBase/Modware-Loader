# NAME

Modware::Loader

# VERSION

version 1.0.0

# NAME

Modware::Loader -  Command line apps for Chado relational database 

[Chado](http://gmod.org/wiki/Introduction\_to\_Chado) is an open-source modular database
schema for biological data. This distribution provides [MooseX::App::Cmd](http://search.cpan.org/perldoc?MooseX::App::Cmd) based command
line applications to import and export biological data from Chado database.

# INSTALLATION

## Using cpanm

- Download a distribution tarball either from a git __tag__ or from <build/develop> branch.
- cpanm <tarball>

## Using Build.PL,  cpan and friends

Download the disribution tarball and follow the instruction in the included __INSTALL__ file.

## From the git repository

This is primarilly intended for authors/developers.

- git checkout git://github.com/dictyBase/Modware-Loader.git
- cpanm -n Dist::Zilla
- dzil listdeps --author --missing | cpanm -n
- dzil install

# AUTHOR

Siddhartha Basu <biosidd@gmail.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Siddhartha Basu.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
