
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

1;
