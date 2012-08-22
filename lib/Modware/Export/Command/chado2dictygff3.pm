package Modware::Export::Command::chado2dictygff3;

use strict;
use namespace::autoclean;
use Moose;
use Bio::GFF3::LowLevel qw/gff3_format_feature/;

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
has 'reference_id'           => (
    is  => 'rw',
    isa => 'Str',
    'documentation' =>
        'reference feature name/ID/accession number. In this case,  only all of its associated features will be dumped'
);
has 'gene_row' =>
    ( is => 'rw', isa => 'DBIx::Class::Row', traits => [qw/NoGetopt/] );

before 'execute' => sub {
    my ($self) = @_;
    my $schema = $self->schema;
    $schema->source('Sequence::Feature')->add_column(
        'is_deleted',
        {   data_type     => 'boolean',
            is_nullable   => 0,
            default_value => 'false'
        }
    );
    if ( $self->reference_id ) {
        $self->register_handler(
            'read_reference_feature',
            sub {
                $self->read_single_reference_feature(@_);
            }
        );
    }
};

sub read_single_reference_feature {
    my ( $self, $dbrow, $type ) = @_;
    return $dbrow->search_related(
        'features',
        {   -or => [
                'me.name'          => $self->reference_id,
                'me.uniquename'    => $self->reference_id,
                'dbxref.accession' => $self->reference_id
            ],
            'type.name' => $type
        },
        {   join => [qw/type dbxref/],
            '+select' =>
                [ { LENGTH => 'me.residues', -as => 'sequence_length' } ],
            cache => 1
        }
    );
}

sub read_gene_feature {
    my ( $self, $dbrow ) = @_;
    return $dbrow->search_related( 'featureloc_srcfeatures', {} )
        ->search_related(
        'feature',
        { 'type.name' => 'gene', 'me.is_deleted' => 0 },
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
        { 'type_2.name' => [ { 'like' => '%RNA%' }, 'pseudogene' ] },
        { join          => 'type' }
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
        my $pseudogene_hash
            = $self->pseudorow2gff3hash( $self->gene_row, $seq_id, '',
            'pseudogene' );
        my $trans_hash = $self->pseudorow2gff3hash( $dbrow, $seq_id, $gene_id,
            'pseudogenic_transcript' );
        $output->print( gff3_format_feature($pseudogene_hash) );
        $output->print( gff3_format_feature($trans_hash) );
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

    my $hash;
    if ( $rs->first->type->name eq 'pseudogene' ) {
        $hash = $self->pseudorow2gff3hash( $dbrow, $seq_id, $trans_id,
            'pseudogenic_exon' );
    }
    else {
        $hash = $self->_dbrow2gff3hash( $dbrow, $seq_id, $trans_id );
    }
    $output->print( gff3_format_feature($hash) );
}

sub pseudorow2gff3hash {
    my ( $self, $dbrow, $seq_id, $parent_id, $type ) = @_;
    my $hashref;
    $hashref->{type}   = $type;
    $hashref->{seq_id} = $seq_id;
    $hashref->{score}  = undef;
    $hashref->{phase}  = undef;

    my $floc_row = $dbrow->featureloc_features->first;
    $hashref->{start} = $floc_row->fmin + 1;
    $hashref->{end}   = $floc_row->fmax;
    if ( my $strand = $floc_row->strand ) {
        $hashref->{strand} = $strand == -1 ? '-' : '+';
    }
    else {
        $hashref->{strand} = undef;
    }

    # source
    my $dbxref_rs
        = $dbrow->search_related( 'feature_dbxrefs', {} )->search_related(
        'dbxref',
        { 'db.name' => 'GFF_source' },
        { join      => 'db' }
        );
    if ( my $row = $dbxref_rs->first ) {
        $hashref->{source} = $row->accession;
    }
    else {
        $hashref->{source} = undef;
    }

    ## -- attributes
    $hashref->{attributes}->{ID} = [ $self->_chado_feature_id($dbrow) ];
    if ( my $name = $dbrow->name ) {
        $hashref->{attributes}->{Name} = [$name];
    }
    $hashref->{attributes}->{Parent} = [$parent_id] if $parent_id;
    my $dbxrefs;
    for my $xref_row ( grep { $_->db->name ne 'GFF_source' }
        $dbrow->secondary_dbxrefs )
    {
        my $dbname = $xref_row->db->name;
        $dbname =~ s/^DB:// if $dbname =~ /^DB:/;
        push @$dbxrefs, $dbname . ':' . $xref_row->accession;
    }
    $hashref->{attributes}->{Dbxref} = $dbxrefs if defined @$dbxrefs;
    return $hashref;
}

sub read_exon_feature {
    my ( $self, $dbrow ) = @_;
    return $dbrow->search_related(
        'feature_relationship_objects',
        { 'type.name' => 'part_of' },
        { join        => 'type' }
        )->search_related(
        'subject',
        { 'type_2.name' => [qw/exon pseudogenic_exon/] },
        { join          => 'type' }
        );
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::chado2dictygff3 - Export GFF3 for Dictyostelium discoideum


