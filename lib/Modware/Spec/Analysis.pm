package Modware::Spec::Analysis;
use namespace::autoclean;
use Moose;

has [qw/name program version source/] => ( isa => 'Str', is => 'rw' );

__PACKAGE__->meta->make_immutable;
1;
