
use strict;

package Modware::Loader::GAF::Row;

use Moose;
use namespace::autoclean;

has 'db' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'dictyBase',
    lazy    => 1
);

has 'taxon' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'taxon:44689',
    lazy    => 1
);

has [qw/qualifier with_from assigned_by date/] => (
    is  => 'rw',
    isa => 'Str'
);

has [qw/gene_id gene_symbol/] => (
    is  => 'rw',
    isa => 'Str'
);

has [qw/go_id aspect db_ref evidence_code/] => (
    is  => 'rw',
    isa => 'Str'
);

has [qw/feature_id cvterm_id pub_id cvterm_id_evidence_code/] => (
    is      => 'rw',
    isa     => 'Int | Undef',
    default => undef,
    lazy    => 1
);

has 'dbxrefs' => (
    traits  => ['Array'],
    is      => 'rw',
    isa     => 'ArrayRef[Int]',
    default => sub { [] },
    handles => {
        set_additional_dbxref => 'push',
        get_dbxref            => 'get',
        has_no_dbxrefs        => 'is_empty',
        has_dbxrefs           => 'count'
    }
);

sub is_valid {
    my ($self) = @_;

    if (   $self->cvterm_id
        && $self->cvterm_id_evidence_code
        && $self->pub_id )
    {
        return 1;
    }
    else {
        return 0;
    }
}

1;
