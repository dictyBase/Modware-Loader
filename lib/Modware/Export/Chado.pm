package Modware::Export::Chado;

use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use YAML qw/LoadFile/;
extends qw/MooseX::App::Cmd::Command/;
with 'MooseX::ConfigFromFile';
with 'Modware::Role::Command::WithIO';
with 'Modware::Role::Command::WithBCS';
with 'Modware::Role::Command::WithReportLogger';

# Module implementation
#

has 'species' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Name of species',
    predicate     => 'has_species'
);

has 'genus' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Name of the genus',
    predicate     => 'has_genus'
);

has 'organism' => (
    isa         => 'Str',
    is          => 'rw',
    traits      => [qw/Getopt/],
    cmd_aliases => 'org',
    documentation =>
        'Common name of the organism whose genomic features will be exported',
    predicate => 'has_organism'
);

has '+configfile' => (
    cmd_aliases   => 'c',
    documentation => 'yaml config file to specify all command line options',
    traits        => [qw/Getopt/]
);

sub get_config_from_file {
    my ( $self, $file ) = @_;
    return LoadFile($file);
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

