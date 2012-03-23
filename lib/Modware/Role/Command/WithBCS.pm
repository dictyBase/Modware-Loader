package Modware::Role::Command::WithBCS;

use strict;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Bio::Chado::Schema;
use Tie::Cache;
use Moose::Util::TypeConstraints;

# Module implementation
#
subtype 'Dsn' => as 'Str' => where { /^dbi:(\w+).+$/ };

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

has 'schema' => (
    is      => 'rw',
    isa     => 'DBIx::Class::Schema',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    builder => '_build_schema',
);

has 'schema_debug' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    documentation => 'Output SQL statements that are executed,  default false'
);

sub _build_schema {
    my ($self) = @_;
    my $schema = Bio::Chado::Schema->connect(
        $self->dsn,
        $self->user,
        $self->password,
        $self->attribute,
        {   on_connect_do => sub {
                tie %{ shift->_dbh->{CachedKids} }, 'Tie::Cache', 100;
                }
        }
    );
    $schema->storage->debug( $self->schema_debug );
    return $schema;
}

1;    # Magic true value required at end of module

