package Modware::Role::Command::WithBCS;

use strict;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Bio::Chado::Schema;
use Tie::Cache;
use Modware::Load::Types qw/Dsn/;
use Modware::Storage::Connection;

# Module implementation
#

has 'connect_info' => (
    traits  => [qw/NoGetopt/],
    is      => 'rw',
    isa     => 'Modware::Storage::Connection', 
    lazy    => 1,
    default => sub {
        return Modware::Storage::Connection->new(
            dsn       => $self->dsn,
            user      => $self->user,
            password  => $self->password,
            attribute => $self->attribute
        );
    }
);

has 'dsn' => (
    is            => 'rw',
    isa           => Dsn,
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
    lazy          => 1,
    default       => sub {
        return { AutoCommit => 1 };
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
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Output SQL statements that are executed,  default to false'
);

sub _build_schema {
    my ($self) = @_;
    my $attribute = $self->attribute;
    if ( $self->dsn =~ /Oracle/i ) {
        $attribute->{LongReadLen} = 2**25;
    }
    my $schema = Bio::Chado::Schema->connect(
        $self->dsn,
        $self->user,
        $self->password,
        $attribute,
        {   on_connect_do => sub {
                tie %{ shift->_dbh->{CachedKids} }, 'Tie::Cache', 100;
                }
        }
    );
    $schema->storage->debug( $self->schema_debug );
    $self->connect_info(
        Modware::Storage::Connection->new(
            dsn             => $self->dsn,
            user            => $self->user,
            password        => $self->password,
            attribute       => $self->attribute,
            extra_attribute => {
                on_connect_do => sub {
                    tie %{ shift->_dbh->{CachedKids} }, 'Tie::Cache', 100;
                    }
            }
        )
    );
    return $schema;
}

1;    # Magic true value required at end of module

