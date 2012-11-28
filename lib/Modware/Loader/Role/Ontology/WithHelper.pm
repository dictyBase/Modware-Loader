package Modware::Loader::Role::Ontology::WithHelper;

use namespace::autoclean;
use Moose::Role;

requires 'schema';

has '_cvrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        get_cvrow   => 'get',
        set_cvrow   => 'set',
        exist_cvrow => 'defined'
    }
);


has '_cvterm_row' => (
    is        => 'rw',
    isa       => 'HashRef',
    traits    => ['Hash'],
    predicate => 'has_cvterm_row',
    default   => sub { {} },
    handles   => {
        get_cvterm_row   => 'get',
        set_cvterm_row   => 'set',
        exist_cvterm_row => 'defined'
    }
);


has '_dbrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        add_dbrow    => 'set',
        get_dbrow    => 'get',
        delete_dbrow => 'delete',
        has_dbrow    => 'defined'
    }
);

1;
