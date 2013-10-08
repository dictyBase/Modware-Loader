package Modware::Role::WithOrganism;
use namespace::autoclean;
use Moose::Role;

requires 'exists_in_datastore';

has 'species' => (
    is            => 'rw',
    isa           => 'Str',
    predicate     => 'has_species'
);

has 'genus' => (
    is            => 'rw',
    isa           => 'Str',
    predicate     => 'has_genus'
);

has 'common_name' => (
    isa         => 'Str',
    is          => 'rw',
    predicate => 'has_organism'
);



1;

=head1 NAME

Modware::Role::WithOrganism - Interface for organism metadata and validation in datastore
