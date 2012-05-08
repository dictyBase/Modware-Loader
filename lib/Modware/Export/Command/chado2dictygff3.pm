package Modware::Export::Command::chado2dictygff3;

use strict;
use namespace::autoclean;
use Moose;

extends qw/Modware::Export::Command::chado2gff3/;

# Other modules:

# Module implementation
#

# this is specific for dicty,  no need to expose them in command line
has '+species'          => ( traits  => [qw/NoGetopt/] );
has '+genus'            => ( traits  => [qw/NoGetopt/] );
has '+organism'         => ( default => 'dicty', traits => [qw/NoGetopt/] );
has '+tolerate_missing' => ( traits  => [qw/NoGetopt/] );
has '+exclude_mitochondrial' => ( traits        => [qw/NoGetopt/] );
has '+only_mitochondrial'    => ( traits        => [qw/NoGetopt/] );
has '+extra_gene_model'      => ( documentation => 'Not implemented yet' );

has 'gene_row' =>
    ( is => 'rw', isa => 'DBIx::Class::Row', traits => [qw/NoGetopt/] );

sub read_gene_feature {
    my ( $self, $dbrow ) = @_;
    return $dbrow->search_related( 'featureloc_srcfeatures', {} )
        ->search_related(
        'feature',
        { 'type.name' => 'gene' },
        { join        => 'type' }
        );
}

sub write_gene_feature {
    my ( $self, $dbrow ) = @_;
    $self->gene_row($dbrow);
}

sub read_transcript_feature {
    my ( $self, $gene_dbrow ) = @_;
    my $trans_rs = $gene_dbrow->search_related(
        'feature_relationship_objects',
        { 'type.name' => 'part_of' },
        { join        => 'type' }
        )->search_related(
        'subject',
        { 'type.name' => [ { 'like' => '%RNA%' }, 'pseudogene' ] },
        { join        => 'type' }
        );
    return $trans_rs->all if $trans_rs->count == 1;
    return $trans_rs->search(
        {   'db.name'          => 'GFF_source',
            'dbxref.accession' => 'dictyBase Curator'
        },
        { join => [ { 'feature_dbxrefs' => { 'dbxref' => 'db' } } ] }
    );
}

sub write_transcript_feature {
    my ( $self, $dbrow, $seq_id, $gene_id, $output ) = @_;

    if ( $dbrow->type->name eq 'pseudogene' ) {

        # dicty pseudogene gene model have to be SO complaint
        # it writes gene and transcript feature
        $self->pseudogene2gff3( $dbrow, $seq_id, $gene_id, $output );
    }
    else {

        #write the cached gene
        my $gene_hash = $self->_dbrow2gff3hash( $self->gene_row, $seq_id );
        return if not defined $gene_hash;
        $output->print( gff3_format_feature($gene_hash) );

        #transcript
        my $trans_hash = $self->_dbrow2gff3hash( $dbrow, $seq_id, $gene_id );
        $output->print( gff3_format_feature($trans_hash) );
    }
}

sub write_exon_feature {
    my ( $self, $dbrow, $seq_id, $trans_id, $output ) = @_;
    my $rs = $self->schema->resultset('Sequence::Feature')
        ->search( { 'dbxref.accession' => $trans_id }, { join => 'dbxref' } );
    if ( $rs->first->type->name eq 'pseudogene' ) {
        $self->pseudoexon2gff3( $dbrow, $seq_id, $trans_id, $output );
    }
    else {
        my $hash = $self->_dbrow2gff3hash( $dbrow, $seq_id, $trans_id );
        $output->print( gff3_format_feature($hash) );
    }
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

<Modware::Export::Command::chado2dictygff3> - [Export GFF3 for Dictyostelium discoideum]


