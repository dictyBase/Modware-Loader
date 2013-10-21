package Modware::Spec::GFF3::Analysis;
use namespace::autoclean;
use Moose;

has [qw/name programversion sourcename/] => ( isa => 'Str', is => 'rw' );
has 'program' => (isa => 'Str', is => 'rw', required => 1);

__PACKAGE__->meta->make_immutable;
1;
