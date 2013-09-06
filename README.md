# NAME

Modware::Loader

# VERSION

version 1.1.0

# NAME

Modware::Loader -  Command line apps for Chado relational database 

[Chado](http://gmod.org/wiki/Introduction\_to\_Chado) is an open-source modular database
schema for biological data. This distribution provides [MooseX::App::Cmd](http://search.cpan.org/perldoc?MooseX::App::Cmd) based command
line applications to import and export biological data from Chado database.

# INSTALLATION

First you have to install [BioPortal](https://github.com/dictyBase/BioPortal-WebService)
distribution from github. Since none of this module is yet to ready for __cpan__,  you have to install it
directly from __github__. For a stable release,  use any of the tarball from git __tag__ and
for a developer release use the __build/develop__ branch. All the recepies below use the
developer release,  suit your script accordingly if you want to use the stable one.

## Using cpanm

### Single step

        $_> curl -o BioPortal-WebService.tar.gz -L -k \
           https://github.com/dictyBase/BioPortal-WebService/archive/build/develop.tar.gz && \
           cpanm -n BioPortal-WebService.tar.gz  && \
           curl -o Modware-Loader.tar.gz -L -k \
           https://github.com/dictyBase/Modware-Loader/archive/build/develop.tar.gz && \
           cpanm -n Modware-Loader.tar.gz && \
           rm BioPortal-WebService.tar.gz Modware-Loader.tar.gz

### Manually

Download the BioPortal-Webservice and Modware-Loader tarballs and invoke __cpanm__ on them.
Read the included __INSTALL__ file for details.

## Using Build.PL,  cpan and friends

Just follow the instuctions in the __INSTALL__ file.

## Directly from the git repository

This is primarilly intended for authors/developers.

        git checkout git://github.com/dictyBase/Modware-Loader.git
        cpanm -n Dist::Zilla
        curl -o BioPortal-WebService.tar.gz -L -k \
           https://github.com/dictyBase/BioPortal-WebService/archive/build/develop.tar.gz && \
        dzil listdeps --author --missing | cpanm -n
        dzil install

# AUTHOR

Siddhartha Basu <biosidd@gmail.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Siddhartha Basu.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
