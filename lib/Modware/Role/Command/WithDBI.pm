package Modware::Role::Command::WithDBI;

use strict;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use DBI;
use Modware::Load::Types qw/Dsn/;

# Module implementation
#

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
        return { AutoCommit => 1, RaiseError => 1 };
    }
);

has 'dbh' => (
    is => 'rw',
    isa => 'DBI::db',
    traits => [qw/NoGetopt/],
    lazy => 1,
    builder => '_build_dbh'
);


sub _build_dbh {
    my ($self) = @_;
    my $attribute = $self->attribute;
    if ( $self->dsn =~ /Oracle/i ) {
        $attribute->{LongReadLen} = 2**25;
    }
    return DBI->connect($self->dsn, $self->user, $self->password, $self->attribute);
}

1;    # Magic true value required at end of module

