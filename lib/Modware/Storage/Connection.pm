package Modware::Storage::Connection;
use namespace::autoclean;
use Moose;

has 'dsn' => (is => 'rw',  isa => 'Str');
has [qw/user password/] => (is => 'rw',  isa => 'Str|Undef');
has 'attribute' => (is => 'rw',  isa => 'HashRef');
has 'extra_attribute' => (is => 'rw',  isa => 'HashRef');
has 'schema_debug' => (is => 'rw',  isa => 'Bool',  default => 0,  lazy => 1);

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

