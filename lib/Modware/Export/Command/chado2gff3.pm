package Modware::Export::Command::chado2gff3;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::GFF3::LowLevel qw/gff3_format_feature/;
extends qw/Modware::Export::Chado/;

# Module implementation
#

has 'write_sequence' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
    documentation =>
        'To write the fasta sequence(s) of reference feature(s),  default is true'
);

has 'exclude_mitochondrial' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Exclude mitochondrial genome,  default is to include if it is present'
);

has 'only_mitochondrial' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Output only mitochondrial genome if it is present,  default is false'
);

has 'include_feature' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    default => sub { [] },
    lazy    => 1,
    handles => {
        all_included_features  => 'elements',
        add_feature_to_include => 'push'
    },
    documentation =>
        'Additional overlapping feature(s) to include in the output'
);

has '_hook_stack' => (
    is      => 'rw',
    isa     => 'HashRef[CodeRef]',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return {
            read_organism => sub { $self->read_organism(@_) },
            read_reference_feature =>
                sub { $self->read_reference_feature(@_) },
            read_seq_id       => sub { $self->read_seq_id(@_) },
            write_meta_header => sub { $self->write_meta_header(@_) },
            write_reference_feature =>
                sub { $self->write_reference_feature(@_) },
            read_gene_feature  => sub { $self->read_gene_feature(@_) },
            write_gene_feature => sub { $self->write_gene_feature(@_) },
            read_transcript_feature =>
                sub { $self->read_transcript_feature(@_) },
            write_transcript_feature =>
                sub { $self->write_transcript_feature(@_) },
            read_exon_feature  => sub { $self->read_exon_feature(@_) },
            write_exon_feature => sub { $self->write_exon_feature(@_) },
            write_cds_feature  => sub { $self->write_cds_feature(@_) },
            write_reference_sequence =>
                sub { $self->write_reference_sequence(@_) }
        };
    },
    handles => {
        get_coderef      => 'get',
        get_all_coderefs => 'keys',
        register_handler => 'set'
    }
);

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
        'The SO type of reference feature,  default is supercontig',
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

    my $dbrow
        = $self->get_coderef('read_organism')->( $schema, $self->organism );

    ## -- writing the header is a must,  so no coderef is necessary
    my $output = $self->output_handler;
    $output->print("##gff-version\t3\n");

    my $reference_rs = $self->get_coderef('read_reference_feature')
        ->( $dbrow, $self->reference_type );

REFERENCE:
    while ( my $ref_dbrow = $reference_rs->next ) {
        $self->get_coderef('write_meta_header')
            ->( $dbrow, $output, $self->taxon_id );

        my $seq_id = $self->get_coderef('read_seq_id')->($ref_dbrow);

        $logger->info("Starting GFF3 output of $seq_id");
        next
            if !$self->get_coderef('write_reference_feature')
                ->( $ref_dbrow, $seq_id, $output );
        my $gene_rs = $self->read_gene_feature($ref_dbrow);
        while ( my $grow = $gene_rs->next ) {
            ## returns array of hashrefs for gene and all of its children
            ## the hashref structure specified is identical to the one described here
            ## https://metacpan.org/module/Bio::GFF3::LowLevel#gff3_parse_feature-line-
            my $arrayref = $self->_gene2gff3_parse_feature( $grow, $seq_id );
            $output->print( gff3_format_feature($_) ) for @$arrayref;
        }
        if ( $self->write_sequence ) {
            $self->read_coderef('write_sequence')
                ->( $ref_dbrow, $seq_id, $output );
        }
        $logger->info("Finished GFF3 output of $seq_id");
    }
    $output->close;
}

sub write_reference_sequence {
    my ( $self, $dbrow, $seq_id, $output ) = @_;
    $output->print( "###FASTA\n>$seq_id\n", $dbrow->residues, "\n" );
}

sub _gene2gff3_parse_feature {
    my ( $self, $gene_dbrow, $seq_id ) = @_;
    my $output = $self->output_handler;
    return
        if !$self->get_coderef('write_gene_feature')
            ->( $gene_dbrow, $seq_id, $output );
    my $gene_id = $self->_chado_feature_id($gene_dbrow);

    my @transcript_dbrows
        = $self->get_coderef('read_transcript_feature')->($gene_dbrow);
    for my $trow (@transcript_dbrows) {
        next
            if !$self->get_coderef('write_transcript_feature')
                ->( $trow, $seq_id, $gene_id, $output );
        my $trans_id    = $self->_chado_feature_id($trow);
        my @exon_dbrows = $self->get_coderef('read_exon_feature')->($trow);

        for my $erow (@exon_dbrows) {
            $self->get_coderef('write_exon_feature')
                ->( $erow, $seq_id, $trans_id, $output );
            if ( $trow->type->name eq 'mRNA' ) {

                # process for CDS here
                $self->get_coderef('write_cds_feature')
                    ->( $erow, $seq_id, $output );
            }
        }
    }
}

sub _dbrow2gff3hash {
    my ( $self, $dbrow, $seq_id, $parent_id, $parent ) = @_;
    my $hashref;
    $hashref->{type}   = $dbrow->type->name;
    $hashref->{score}  = undef;
    $hashref->{seq_id} = $seq_id;

    my $floc_row = $dbrow->featureloc_features->first;
    $hashref->{start}  = $floc_row->fmin + 1;
    $hashref->{end}    = $floc_row->fmax;
    $hashref->{strand} = $floc_row->strand == -1 ? '-' : '+';

    if ( $hashref->{type} eq 'CDS' ) {
        ## -- phase for CDS
    }
    else {
        $hashref->{phase} = undef;
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
        $self->logger->warn(
            $dbrow->type->name,
            " feature ",
            $dbrow->uniquename,
            " do not have GFF3 source defined in the database: it is skipped from output"
        );
        return;
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
        push @$dbxrefs, $xref_row->db->name . ':' . $xref_row->accession;
    }
    $hashref->{attributes}->{Dbxref} = $dbxrefs if defined @$dbxrefs;
    return $hashref;
}

sub _chado_feature_id {
    my ( $self, $dbrow ) = @_;
    if ( my $id = $dbrow->dbxref->accession ) {
        return $id;
    }
    else {
        return $dbrow->uniquename;
    }
}

sub _children_dbrows {
    my ( $self, $parent_row, $relation, $type ) = @_;
    $type = { -like => $type } if $type =~ /^%/;
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

sub read_organism {
    my ( $self, $schema, $organism ) = @_;
    my $org_rs = $schema->resultset('Organism::Organism')->search(
        { 'common_name' => $self->organism },
        {   select => [
                qw/species genus
                    common_name organism_id/
            ]
        }
    );

    my $dbrow = $org_rs->first;
    if ( !$dbrow ) {
        die "Could not find ", $self->organism, " in chado database\n";
    }
    return $dbrow;
}

sub read_reference_feature {
    my ( $self, $dbrow, $type ) = @_;
    my $reference_rs
        = $dbrow->search_related( 'feature', {} )->search_related(
        { 'type.name' => $type },
        { join        => 'type' },
        { prefetch    => 'dbxref' }
        );
    die "no reference feature(s) found for organism ", $dbrow->common_name,
        "\n"
        if !$reference_rs->count;
    return $reference_rs;
}

sub read_seq_id {
    my ( $self, $row ) = @_;
    my $seq_id = $row->name ? $row->name : $row->uniquename;
    return $seq_id;
}

sub write_meta_header {
    my ( $self, $dbrow, $output, $taxon_id ) = @_;
    my $base = 'http://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id=';
    if ($taxon_id) {
        $output->print( $base . $self->taxon_id );
        return;
    }
    $output->print( $base . $dbrow->genus . ' ' . $dbrow->species );
}

sub write_reference_feature {
    my ( $self, $dbrow, $output, $seq_id ) = @_;
    my $start = 1;
    if ( my $end = $dbrow->seqlen ) {
        $output->print("##sequence-region\t$seq_id\t$start\t$end\n");
    }
    else {
        warn "$seq_id has no length defined:skipped from export\n";
        return;
    }

    my $hashref;
    $hashref->{type}   = $dbrow->type->name;
    $hashref->{score}  = undef;
    $hashref->{seq_id} = $seq_id;
    $hashref->{start}  = 1;
    $hashref->{end}    = $dbrow->seqlen;
    $hashref->{strand} = undef;
    $hashref->{phase}  = undef;
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
        $self->logger->warn(
            $dbrow->type->name,
            " feature ",
            $dbrow->uniquename,
            " do not have GFF3 source defined in the database: it is skipped from output"
        );
        return;
    }

    ## -- attributes
    $hashref->{attributes}->{ID} = [ $self->_chado_feature_id($dbrow) ];
    if ( my $name = $dbrow->name ) {
        $hashref->{attributes}->{Name} = [$name];
    }
    my $dbxrefs;
    for my $xref_row ( grep { $_->db->name ne 'GFF_source' }
        $dbrow->secondary_dbxrefs )
    {
        push @$dbxrefs, $xref_row->db->name . ':' . $xref_row->accession;
    }
    $hashref->{attributes}->{Dbxref} = $dbxrefs if defined @$dbxrefs;
    $output->print( gff3_format_feature($hashref) );
}

sub read_gene_feature {
    my ( $self, $dbrow ) = @_;
    return $self->_children_dbrows( $dbrow, 'part_of', 'gene' );
}

sub read_exon_feature {
    my ( $self, $dbrow ) = @_;
    return $self->_children_dbrows( $dbrow, 'part_of', 'exon' );
}

sub read_transcript_feature {
    my ( $self, $dbrow ) = @_;
    return $self->_children_dbrows( $dbrow, 'part_of', '%RNA' );
}

sub write_gene_feature {
    my ( $self, $dbrow, $seq_id, $output ) = @_;
    my $gene_hash = $self->_dbrow2gff3hash( $dbrow, $seq_id );
    return if not defined $gene_hash;
    $output->print( gff3_format_feature($gene_hash) );
    return 1;
}

sub write_transcript_feature {
    my ( $self, $dbrow, $seq_id, $gene_id, $output ) = @_;
    my $hash = $self->_dbrow2gff3hash( $dbrow, $seq_id, $gene_id );
    $output->print( gff3_format_feature($hash) );
    return 1;
}

sub write_exon_feature {
    my ( $self, $dbrow, $seq_id, $trans_id, $output ) = @_;
    my $hash = $self->_dbrow2gff3hash( $dbrow, $seq_id, $trans_id );
    $output->print( gff3_format_feature($hash) );
    return 1;
}

sub write_cds_feature {
    my ( $self, $dbrow, $seq_id, $output ) = @_;
}

sub read_reference_feature_without_mito {
    my ( $self, $dbrow, $type ) = @_;
    my $mito_rs = $dbrow->search_related(
        'features',
        {   'type.name'   => $type,
            'type_2.name' => 'mitochondrial_DNA',
            'cv.name'     => 'sequence'
        },
        { join => [ 'type', { 'featureprops' => { 'type' => 'cv' } } ] }
    );

    my $nuclear_rs;
    if ( $rs->count ) {    ## -- mitochondrial genome is present
        $nuclear_rs = $dbrow->search_related(
            'features',
            {   'feature_id' => {
                    -not_in => $mito_rs->get_column('feature_id')->as_query
                },
                'type.name' => $type
            },
            { join => 'type' }
        );
    }
    else {                 # no mito genome
        $nuclear_rs = $dbrow->search_related(
            'features',
            { 'type.name' => $type },
            { join        => 'type' }
        );
    }

    die "no reference feature found for organism ", $dbrow->common_name, "\n"
        if !$nuclear_rs->count;
    return $nuclear_rs;
}

sub read_mito_reference_feature {
    my ( $self, $dbrow, $type ) = @_;
    my $rs = $dbrow->search_related(
        'features',
        {   'type.name'   => $type,
            'type_2.name' => 'mitochondrial_DNA',
            'cv.name'     => 'sequence'
        },
        { join => [ 'type', { 'featureprops' => { 'type' => 'cv' } } ] }
    );
    die "no mitochondrial reference feature(s) found for organism ",
        $dbrow->common_name, "\n"
        if !$rs->count;
    return $rs;
}

before 'execute' => sub {
    my ($self) = @_;
    if ( $self->exclude_mitochondrial ) {
        $self->register_handler( 'read_reference_feature' =>
                sub { $self->read_reference_feature_without_mito(@_) } );
    }
    if ( $self->only_mitochondrial ) {
        $self->register_handler(
            'read_reference_feature' => sub {
                $self->read_mito_reference_feature(@_);
            }
        );
    }
};

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Export GFF3 file from chado database

