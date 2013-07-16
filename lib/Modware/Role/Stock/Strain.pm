
use strict;

package Modware::Role::Stock::Strain;

use Moose::Role;
use namespace::autoclean;

has '_dbxref_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_dbxref_row    => 'set',
        get_dbxref_row    => 'get',
        delete_dbxref_row => 'delete',
        has_dbxref_row    => 'defined'
    }
);

=item find_dbxref_accession (Int $dbxref_id)
=cut

sub find_dbxref_accession {
    my ( $self, $dbxref_id ) = @_;
    if ( $self->has_dbxref_row($dbxref_id) ) {
        return $self->get_dbxref_row($dbxref_id)->accession;
    }
    my $row
        = $self->schema->resultset('General::Dbxref')
        ->search( { dbxref_id => $dbxref_id },
        { select => [qw/dbxref_id accession/] } );
    if ( $row->count > 0 ) {
        $self->set_dbxref_row( $dbxref_id, $row->first );
        return $self->get_dbxref_row($dbxref_id)->accession;
    }
}

has '_strain_invent_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_strain_invent_row => 'set',
        get_strain_invent_row => 'get',
        has_strain_invent     => 'defined'
    }
);

=item find_strain_inventory (Str $dbs_id)

=cut

sub find_strain_inventory {
    my ( $self, $dbs_id ) = @_;
    if ( $self->has_strain_invent($dbs_id) ) {
        return $self->get_strain_invent_row($dbs_id);
    }
    my $old_dbxref_id
        = $self->schema->resultset('General::Dbxref')
        ->search( { accession => $dbs_id },
        { select => [qw/dbxref_id accession/] } )->first->dbxref_id;
    my $strain_invent_rs
        = $self->legacy_schema->resultset('StockCenterInventory')->search(
        { 'strain.dbxref_id' => $old_dbxref_id },
        {   join   => 'strain',
            select => [
                qw/me.location me.color me.no_of_vials me.obtained_as me.stored_as me.storage_date/
            ],
            cache => 1
        }
        );
    if ( $strain_invent_rs->count > 0 ) {
        $self->set_strain_invent_row( $dbs_id, $strain_invent_rs );
        return $self->get_strain_invent_row($dbs_id);
    }

    #else {
    #    $self->dual_logger->warn("Cannot find strain inventory for $dbs_id");
    #    return 0;
    #}
}

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

has '_cvterm_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_cvterm_row  => 'set',
        get_cvterm_row  => 'get',
        has_cvterm_name => 'defined'
    }
);

sub find_cvterm_name {
    my ( $self, $cvterm_id ) = @_;

    if ( $self->has_cvterm_name($cvterm_id) ) {
        return $self->get_cvterm_row($cvterm_id)->name;
    }
    my $row = $self->schema->resultset('Cv::Cvterm')->search(
        { cvterm_id => $cvterm_id },
        {   select => [qw/cvterm_id name/],
            cache  => 1
        }
    );
    if ( $row->count > 0 ) {
        $self->set_cvterm_row( $cvterm_id, $row->first );
        return $self->get_cvterm_row($cvterm_id)->name;
    }
}

1;
