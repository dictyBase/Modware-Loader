
use strict;

package Modware::Role::Stock::Commons;

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

sub resolve_references {
    my ( $self, $pubmedid, $internal, $other_ref ) = @_;
    my @pmids;

    if ($pubmedid) {
        if ( $pubmedid =~ /,/ ) {
            @pmids = split( /,/, $pubmedid );
        }
        else {
            push( @pmids, $self->trim($pubmedid) )
                if $pubmedid =~ /[0-9]{6,10}/;
        }
    }
    if ($other_ref) {
        if ( $other_ref =~ /[,;\s\/]/ ) {
            my @ref_data = split( /[,;\s\/]/, $other_ref );
            foreach my $ref (@ref_data) {
                if ( $ref =~ /[0-9]{6,10}/ ) {
                    push( @pmids, $self->trim($ref) );
                }
            }
        }
        else {
            push( @pmids, $self->trim($other_ref) )
                if $other_ref =~ /[0-9]{6,10}/;
        }
    }
    return @pmids;
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Commons - 

=head1 DESCRIPTION



=cut 
