
use strict;

package Modware::Role::Stock::Plasmid;

use Moose::Role;
use namespace::autoclean;

has '_feature_dbxref_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_feature_dbxref_row => 'set',
        get_feature_dbxref_row => 'get',
        has_feature_dbxref     => 'defined'
    }
);

sub find_gene_id {
    my ( $self, $feature_id ) = @_;

    if ( $self->has_feature_dbxref($feature_id) ) {
        return $self->get_feature_dbxref_row($feature_id)->accession;
    }
    my $row = $self->schema->resultset('General::Dbxref')->search(
        { 'features.feature_id' => $feature_id },
        {   join   => 'features',
            select => [qw/dbxref_id accession/],
            cache  => 1
        }
    );
    if ( $row->count > 0 ) {
        $self->set_feature_dbxref_row( $feature_id, $row->first );
        return $self->get_feature_dbxref_row($feature_id)->accession;
    }
}

1;
