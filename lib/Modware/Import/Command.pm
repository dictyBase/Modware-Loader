
use strict;

package Modware::Import::Command;

use Bio::Chado::Schema;
use Moose;
use namespace::autoclean;
use Moose::Util::TypeConstraints;
use Cwd;
use File::Spec::Functions qw/catfile catdir rel2abs/;
use File::Basename;
use Time::Piece;
use YAML qw/LoadFile/;
use Path::Class::File;

extends qw/MooseX::App::Cmd::Command/;
with 'MooseX::ConfigFromFile';

subtype 'DataDir'  => as 'Str' => where { -d $_ };
subtype 'DataFile' => as 'Str' => where { -f $_ };
subtype 'Dsn'      => as 'Str' => where {/^dbi:(\w+).+$/};

has '+configfile' => (
    cmd_aliases   => 'c',
    documentation => 'yaml config file to specify all command line options',
    traits        => [qw/Getopt/],
    default       => sub { return undef }
);

has 'data_dir' => (
    is          => 'rw',
    isa         => 'DataDir',
    traits      => [qw/Getopt/],
    cmd_flag    => 'dir',
    cmd_aliases => 'd',
    documentation =>
        'Folder under which input and output files can be configured to be written',
    builder => '_build_data_dir',
    lazy    => 1
);

sub _build_data_dir {
    return rel2abs(cwd);
}

has 'input' => (
    is            => 'rw',
    isa           => 'DataFile',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'i',
    documentation => 'Name of the input file'
);

has 'dsn' => (
    is            => 'rw',
    isa           => 'Dsn',
    documentation => 'database DSN',
    required      => 1
);

has 'user' => (
    is            => 'rw',
    isa           => 'Str',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'u',
    documentation => 'database user'
);

has 'password' => (
    is            => 'rw',
    isa           => 'Str',
    traits        => [qw/Getopt/],
    cmd_aliases   => [qw/p pass/],
    documentation => 'database password'
);

has 'schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    builder => '_build_chado',
);

sub _build_chado {
    my ($self) = @_;
    my $schema = Bio::Chado::Schema->connect( $self->dsn, $self->user,
        $self->password );
    return $schema;
}

sub get_config_from_file {
    my ( $self, $file ) = @_;
    return LoadFile($file);
}

1;

__END__

=head1 NAME

Modware::Import::Command - Base class for writing import command module

=head1 DESCRIPTION


=cut
