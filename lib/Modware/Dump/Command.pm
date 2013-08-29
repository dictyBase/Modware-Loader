
use strict;

package Modware::Dump::Command;

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
with 'Modware::Role::Stock::Export::Chado::WithOracle';

subtype 'DataDir'  => as 'Str' => where { -d $_ };
subtype 'DataFile' => as 'Str' => where { -f $_ };
subtype 'Dsn'      => as 'Str' => where {/^dbi:(\w+).+$/};

has '+configfile' => (
    cmd_aliases   => 'c',
    documentation => 'yaml config file to specify all command line options',
    traits        => [qw/Getopt/],
    default       => sub { return undef }
);

has 'output_dir' => (
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

has 'input' => (
    is            => 'rw',
    isa           => 'DataFile',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'i',
    documentation => 'Name of the input file'
);

has 'output' => (
    is            => 'rw',
    isa           => 'Str',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'o',
    documentation => 'Name of the output file'
);

has 'output_handler' => (
    is      => 'ro',
    isa     => 'IO::Handle',
    traits  => [qw/NoGetopt/],
    default => sub {
        my $self = shift;
        Path::Class::File->new( $self->output )->openw;
    },
    lazy => 1
);

has 'attribute' => (
    is            => 'rw',
    isa           => 'HashRef',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'attr',
    documentation => 'Additional database attribute',
    default       => sub {
        { 'LongReadLen' => 2**25, AutoCommit => 1 };
    }
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
        $self->password, $self->attribute );
    my $new_schema = $self->transform_schema($schema);
    return $new_schema;

    # $self->meta->make_mutable;
    # my $engine = 'Modware::Role::Stock::Chado::WithOracle';
    # ensure_all_roles( $self, $engine );
    # $self->meta->make_immutable;
}

has 'legacy_dsn' => (
    is            => 'rw',
    isa           => 'Dsn',
    documentation => 'Legacy database DSN',
    required      => 1
);

has 'legacy_user' => (
    is            => 'rw',
    isa           => 'Str',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'u',
    documentation => 'Legacy database user'
);

has 'legacy_password' => (
    is            => 'rw',
    isa           => 'Str',
    traits        => [qw/Getopt/],
    cmd_aliases   => [qw/p pass/],
    documentation => 'Legacy database password'
);

has 'legacy_schema' => (
    is      => 'rw',
    isa     => 'Modware::Legacy::Schema',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    builder => '_build_legacy_schema',
);

sub _build_legacy_schema {
    my ($self) = @_;
    my $schema = Modware::Legacy::Schema->connect(
        $self->legacy_dsn,      $self->legacy_user,
        $self->legacy_password, $self->attribute
    );
    return $schema;
}

sub _build_data_dir {
    return rel2abs(cwd);
}

sub get_config_from_file {
    my ( $self, $file ) = @_;
    return LoadFile($file);
}

1;

__END__

=head1 NAME

Modware::Dump::Command - Base class for writing dump command module

=head1 DESCRIPTION


=cut
