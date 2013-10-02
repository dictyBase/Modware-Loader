package Modware::Loader::Role::WithChado;

use namespace::autoclean;
use Moose::Role;

requires
    qw(schema bulk_load alter_tables reset_tables logger);

has 'sqlmanager' => (
    is      => 'rw',
    isa     => 'SQL::Library',
);

1;

