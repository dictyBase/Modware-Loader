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

You need to install 2/3 dependencies from __github__, rest of them would be pulled from __CPAN__ as needed.
Install using __cpanm__ is highly recommended.
Use a latest version of [cpanm](https://metacpan.org/module/cpanm), at least 1.6 is needed.

## Latest release 

        cpanm -n  git://github.com/dictyBase/BioPortal-WebService.git
        cpanm -n  git://github.com/dictyBase/Modware-Loader.git

If you install without (-n/notest flag) then install __Test::Chado__ before you install __BioPortal-Webservice__.

        cpanm git://github.com/dictyBase/Test-Chado.git

## Any particular release

Download the respective tarballs from their release pages in github and invoke __cpanm__ on them locally.

- BioPortal-WebService [release page](https://github.com/dictyBase/BioPortal-WebService/releases)
- Test-Chado [release page](https://github.com/dictyBase/Test-Chado/releases)
- Modware-Loader [release pages](https://github.com/dictyBase/Modware:Loader/releases)

### Using Build.PL,  cpan and friends

Just follow the instuctions in the __INSTALL__ file.

# Quick start

Run any one of the following command

- modware-export
- modware-load
- modware-transform
- modware-update

Then follow the instructions to run any of the subcommand. Invoking the subcommand will display further help which is more or less self-explanatory.

# Documentation/Examples

- [Exporting annotations](http://dictybase.github.io/blog/2013/03/06/exporting-discoideum-annotations/)
- [Converting tblastn alignments to GFF3 format](http://dictybase.github.io/refining-tblastn-protein-alignments/index.html)

# AUTHOR

Siddhartha Basu <biosidd@gmail.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Siddhartha Basu.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
