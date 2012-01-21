package Modware::Export::Command::chado2gff3;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::GFF3::LowLevel;
extends qw/Modware::Export::Chado/;

# Module implementation
#

has 'organism' => (
    isa         => 'Str',
    is          => 'rw',
    traits      => [qw/Getopt/],
    required    => 1,
    cmd_aliases => 'org',
    documentation =>
        'Common name of the organism whose genomic features will be exported'
);

has 'reference_type' => (
    isa         => 'Str',
    is          => 'rw',
    traits      => [qw/Getopt/],
    cmd_aliases => 'rt',
    documentation =>
        'The SO type of reference feature,  default is supecontig',
    default => 'supercontig',
    lazy    => 1
);

has 'taxon_id' => (
    isa           => 'Int',
    is            => 'rw',
    predicate     => 'has_taxon_id',
    documentation => 'NCBI taxon id'
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;
    my $schema = $self->schema;

    my $org_rs = $schema->resultset('Organism::Organism')
        ->search( { 'common_name' => $self->organism } );

    my $dbrow = $org_rs->first;
    if ( !$dbrow ) {
        die "Could not find ", $self->organism, " in chado database\n";
    }

    my $output = $self->output;
    $output->print("##gff-version\t3\n");

    my $reference_rs => $org_rs->search_related(
        'features',
        { 'type.name' => $self->reference_type },
        { join        => 'type' }
    );

REFERENCE:
    while ( my $ref_dbrow = $reference_rs->next ) {
        my $seq_id = $self->_seq_id($ref_dbrow);
        my $start  = 1;
        if ( my $end = $ref_dbrow->seqlen ) {
            $output->print("##sequence-region\t$seqid\t$start\t$end\n");
        }
        else {
            warn "$seq_id has no length defined:skipped from export\n";
            next REFERENCE;
        }
        $output->print( "##species\t", $self->_species_uri($ref_dbrow),
            "\n" );

        my $refhash = $self->_dbrow2gff3hash($ref_dbrow);
        $output->print( gff3_format_feature($refhash) );

        my $gene_rs = $self->_children_dbrow( $ref_dbrow, 'part_of', 'gene' );
        while ( my $grow = $gene_rs->next ) {
            ## returns array of hashrefs for gene and all of its children
            ## the hashref structure specified is identical to the one described here
            ## https://metacpan.org/module/Bio::GFF3::LowLevel#gff3_parse_feature-line-
            my $arrayref = $self->_gene2gff3_parse_feature( $grow, $seq_id );
            $output->print( gff3_format_feature($_) ) for @$arrayref;
        }
        $output->print( "###FASTA\n>$seq_id\n", $ref_dbrow->residues, "\n" );
        $logger->info("Finished GFF3 output of $seq_id");
    }
    $output->close;
}

sub _gene2gff3_parse_feature {
    my ( $self, $gene_dbrow, $seq_id ) = @_;
    my $arrayref;
    my $gene_hash = $self->_dbrow2gff3hash( $gene_dbrow, $seq_id );
    return if not defined $gene_hash;
    push @$arrayref, $gene_hash;

    my $gene_id = $self->_chado_feature_id($gene_dbrow);
    my @transcript_dbrows
        = $self->_children_dbrows( $gene_dbrow, 'part_of', '%RNA' );
    for my $trow (@transcript_dbrows) {
        my $thash = $self->_dbrow2gff3hash( $trow, $seq_id, $gene_id );
        push @$arrayref, $thash;
        my $trans_id = $self->_chado_feature_id($trow);
        for my $erow ( $self->_children_dbrows( $erow, 'part_of', 'exon' ) ) {
            my $exhash = $self->_dbrow2gff3hash( $erow, $seq_id, $trans_id );
            push @$arrayref, $exhash;
        }
        if ( $trow->type->name eq 'mRNA' ) {

            # process for CDS here
        }
    }
}

sub _dbrow2gff3hash {
    my ( $self, $dbrow, $seq_id, $parent_id ) = @_;
    my $hashref;

    $hashref->{type}  = $dbrow->type->name;
    $hashref->{score} = undef;
    if ($seq_id) {
        $hashref->{seq_id} = $seq_id;
        $hashref->{start}  = 1;
        $hashref->{end}    = $dbrow->seqlen;
        $hashref->{strand} = undef;
    }
    else {
        $hashref->{seq_id} = undef;
        $floc_row          = $dbrow->featureloc_features->first;
        $hashref->{start}  = $floc_row->fmin + 1;
        $hashref->{end}    = $floc_row->fmax;
        $hashref->{strand} = $floc_row->strand == -1 ? '-' : '+';
    }
    if ( $hashref->{type} eq 'CDS' ) {
        ## -- phase for CDS
    }
    else {
        $hashref->{phase} = undef;
    }

    my $dbxref_rs = $dbrow->search_related( 'feature_dbxrefs', {} )
        ->search( 'dbxref', { 'db.name' => 'GFF_source' }, { join => 'db' } );
    if ( my $row = $dbxref_rs->first ) {
        $hashref->{source} = $row->accession;
    }
    else {
        $self->logger->warn(
            $dbrow->type->name,
            " feature ",
            $dbrow->uniquename,
            " do not have GFF3 source defined in the database: it is skipped from output"
        );
        return;
    }

	## -- attributes
    $hashref->{attributes}->{ID} = [ $self->_chado_feature_id ];
    if ( my $name = $dbrow->name ) {
        $hashref->{attributes}->{Name} = [$name];
    }
    $hashref->{attributes}->{Parent} = [$parent_id] if $parent_id;
    my $dbxrefs;
    for my $xref_row ( grep { $_->db->name ne 'GFF_source' }
        $dbrow->secondary_dbxrefs )
    {
        push @$dbxrefs, $xref_row->db->name . ':' . $xref_row->accession;
    }
    $hashref->{attributes}->{Dbxref} = $dbxrefs;
    return $hashref;
}

sub _chado_feature_id {
    my ( $self, $dbrow ) = @_;
    if ( my $id = $dbrow->dbxref->accession ) {
        return $id;
    }
    else {
        return $dbrow->uniquename `;
	}
}

sub _gene_rs {
    my ( $self, $dbrow ) = @_;
    return $dbrow->search_related(
        'feature_relationship_objects',
        { 'type.name' => 'part_of' },
        { join        => 'type' }
        )->search_related(
        'subject',
        { 'type_2.name' => 'gene' },
        { join          => 'type' }
        );
}

sub _children_dbrows {
    my ( $self, $parent_row, $relation,  $type ) = @_;
    $type = {-like => $type} if $type =~ /^%/;
    return $parent_row->search_related(
        'feature_relationship_objects',
        { 'type.name' => $relation },
        { join        => 'type' }
        )->search_related(
        'subject',
        { 'type_2.name' => $type },
        { join          => 'type' }
        );
}

sub _seq_id {
    my ( $self, $row ) = @_;
    my $seq_id = $row->name ? $row->name : $row->uniquename;
    return $seq_id;
}

sub _species_uri {
    my ( $self, $dbrow ) = @_;
    my $base = 'http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=';
    return $self->taxon_id if $base . $self->has_taxon_id;
    return uri_escape( $base . $dbrow->genus . ' ' . $dbrow->species );

}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Export GFF3 file from chado database

