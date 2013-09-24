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

## Using cpanm
Use a latest version of [cpanm](https://metacpan.org/module/cpanm), at least 1.6 is needed.
You need to install 2/3 dependencies from __github__, rest of them would be pulled from __CPAN__ as needed.


    cpanm -n  git://github.com/dictyBase/BioPortal-WebService.git
    cpanm -n  git://github.com/dictyBase/Modware-Loader.git

If you install without (-n/notest flag) then add B<Test::Chado>

Use a latest version of [cpanm](https://metacpan.org/module/cpanm), at least 1.6 is needed.
You need to install 2/3 dependencies from __github__, rest of them would be pulled from __CPAN__ as needed.

        cpanm -n  git://github.com/dictyBase/BioPortal-WebService.git
        cpanm -n  git://github.com/dictyBase/Modware-Loader.git

If you install without (-n/notest flag) then add __Test::Chado__

        cpanm git://github.com/dictyBase/Test-Chado.git

## Manually

Download the BioPortal-Webservice and Modware-Loader tarballs from github master and invoke __cpanm__ on them.

- BioPortal-WebService [tarball](https://github.com/dictyBase/BioPortal-WebService/archive/master.tar.gz)
- Test-Chado [tarball](https://github.com/dictyBase/Test-Chado/archive/master.tar.gz)
- Modware-Loader [tarball](https://github.com/dictyBase/Modware:Loader/archive/master.tar.gz)

### Using Build.PL,  cpan and friends

Just follow the instuctions in the __INSTALL__ file.

### Directly from the git repository

This is primarilly intended for authors/developers.

        git checkout git://github.com/dictyBase/Modware-Loader.git
        cpanm -n Dist::Zilla
        cpanm git://github.com/dictyBase/BioPortal-WebService.git
        cpanm git://github.com/dictyBase/Test-Chado.git
        cpanm git://github.com/dictyBase/Modware-Loader.git
        dzil listdeps --author --missing | cpanm -n
        dzil install

# AUTHOR

Siddhartha Basu <biosidd@gmail.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Siddhartha Basu.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
