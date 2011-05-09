package Modware::Export::GAF;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Try::Tiny;
use File::Spec::Functions;
use GOBO::TermNode;
use GOBO::Annotation;
use GOBO::Writers::GAFWriter;
use GOBO::Evidence;
use GOBO::Gene;
use GOBO::Graph;
use Time::Piece;

extends qw/Modware::Export::Command/;

# Module implementation
#

has '+input'          => ( traits => [qw/NoGetopt/] );
has '+data_dir'       => ( traits => [qw/NoGetopt/] );
has '+output_handler' => ( traits => [qw/NoGetopt/] );

has 'sample_run' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Used for dumping only first 2500 records, use for debugging purpose'
);

has 'include_obsolete' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    documentation => 'To include obsolete annotations,  default is off'
);

has 'gafcv' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'The cv namespace for storing gaf metadata such as source, with, qualifier and date column in chado database'
);

has 'date_term' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Cv term for storing date column'
);

has 'with_term' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Cv term for storing with column'
);

has 'source_term' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Cv term for storing source column'
);

has 'qual_term' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Cv term for storing qualifier column'
);

has 'taxon_id' => (
    is            => 'rw',
    isa           => 'Int',
    documentation => 'The NCBI taxon id'
);

has 'source_database' => (
    is          => 'rw',
    isa         => 'Str',
    traits      => [qw/Getopt/],
    cmd_aliases => 'source_db',
    documentation =>
        'The source database from which identifier is drawn,  represents column 1 of GAF2.0'
);

has 'pubmed_namespace' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    default => 'PMID'
);

has 'go_namespace' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    default => 'GO'
);

has 'taxon_namespace' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    default => 'taxon'
);

has 'common_name' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Common name of the organism'
);

has 'source_url' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Canonical url for the source database'
);

has 'chunk_threshold' => (
    is      => 'rw',
    isa     => 'Int',
    default => 5000,
    documentation =>
        'Threshold for no of entries that will be flushed to file after processing'
);

sub execute {
    my ($self) = @_;
    my $schema = $self->chado;
    my $log    = $self->dual_logger;
    my $graph  = GOBO::Graph->new;

    my $writer = GOBO::Writers::GAFWriter->new( file => $self->output );
    $writer->add_to_header('gaf-version: 2.0');
    $writer->add_to_header( Time::Piece->new->mdy('/') );
    $writer->add_to_header(
        $self->source_database . ' (' . $self->source_url . ')' );
    $writer->add_to_header(' ');

    my $base_query = {
    	'cvterm.is_obsolete' => 0, 
        'cv.name' => {
            -in => [
                qw/molecular_function biological_process
                    cellular_component/
            ]
        },
        'organism.common_name' => $self->common_name,

    };

    if ($self->include_obsolete) {
    	delete $base_query->{'cvterm.is_obsolete'};
    }

    my $assoc_rs = $schema->resultset('Sequence::FeatureCvterm')->search(
        $base_query,
        {   join => [ { 'cvterm' => 'cv' }, { 'feature' => 'organism' } ],
            prefetch => 'pub',
            cache    => 1,
        }
    );


    if ( $self->sample_run ) {
        $assoc_rs = $assoc_rs->search( {}, { rows => 2500 } );
    }

    $log->info( 'going to process ', $assoc_rs->count, ' entries' );

    my $increment = 1;
    while ( my $assoc = $assoc_rs->next ) {
        my $anno = GOBO::Annotation->new;
        my $gene = GOBO::Gene->new;

        ## -- get the associated node(gene feature generally)
        my $feat = $assoc->feature;
        my $gene_feat;
        if ( $feat->type->name ne 'gene' ) {    ## for gaf2.0
            my $node = GOBO::TermNode->new;
            $node->gp_type( $feat->type->name );
            $node->id( $feat->dbxref->accession );
            $gene_feat = $self->feat2gene($feat);
            $anno->specific_node($node);
            $anno->description( $self->get_description($feat) );
        }
        else {
            $gene_feat = $feat;
            $gene->gp_type( $gene_feat->type->name );
            $anno->description( $self->get_description($gene_feat) );
        }
        $gene->id(
            $self->source_database . ':' . $gene_feat->dbxref->accession );
        $gene->label( $gene_feat->uniquename );
        $gene->taxon( $self->taxon_namespace . ':' . $self->taxon_id );

        my $syn_rs
            = $feat->feature_synonyms->search_related( 'alternate_names',
            {} );
        if ($syn_rs) {
            $gene->add_synonym( $_->name ) for $syn_rs->all;
        }
        $anno->node($gene);

        ## -- have to get the product/gene product ????

        ## -- get the target go term
        my $cvterm = $assoc->cvterm;
        my $target = GOBO::TermNode->new;
        $target->id( $self->go_namespace . ':' . $cvterm->dbxref->accession );
        $target->namespace( $cvterm->cv->name );
        $anno->target($target);

        #Dbxrefs
        $anno->provenance( $self->get_provenance($assoc) );
        $anno->add_xrefs( $self->get_xrefs($assoc) );

        #common rs to fetch the various feature_cvterm_props
        my $fcvprop_rs = $assoc->feature_cvtermprops->search(
            { 'cv.name' => $self->gafcv },
            { join      => [ { 'type' => 'cv' } ] }
        );

        #qualifiers
        $anno->negated(1) if $assoc->is_not;
        $anno->add_qualifier($_) for $self->get_qualifiers($fcvprop_rs);

        #evidence and with field
        my $evidence    = GOBO::Evidence->new;
        my $evidence_rs = $assoc->feature_cvtermprops->search_related(
            'type',
            { 'cv.name' => { -like => 'evidence_code%' } },
            { join      => 'cv' }
            )->search_related(
            'cvtermsynonym_cvterms',
            { 'type_2.name' => { -in => [qw/EXACT RELATED/] } },
            { join          => 'type' }
            );

        $evidence->ev_type( $evidence_rs->first->synonym_ );
        $evidence->supporting_entities( $self->get_with_column($fcvprop_rs) );
        $anno->evidence($evidence);
        $anno->source( $self->get_source_column($fcvprop_rs) );
        $anno->date( $self->get_date_column($fcvprop_rs) );
        $graph->add_annotation($anno);

        $self->inc_process;

        if ( ( $self->process_count / $self->chunk_threshold ) >= $increment )
        {
            $log->info( "processed ", $self->process_count, " entries" );
            $increment++;

            $writer->write_chunk( graph => $graph );
            $writer->clear_graph;
            $graph = GOBO::Graph->new;
            $log->info( "Written ", $self->process_count, " entries so far" );
        }
    }

    if ( defined $graph and @{ $graph->annotations } )
    {    ## -- write the rest of it
        $writer->write_chunk( graph => $graph );
    }

    $log->info( "written ", $self->process_count, " entries in GAF2.0 file" );
}

sub feat2gene {
    return;
}

sub get_description {
    return;
}

sub get_provenance {
    my ( $self, $row ) = @_;
    $self->pubmed_namespace . ':' . $row->pub->uniquename;
}

sub get_xrefs {
    my ( $self, $row ) = @_;
    my $dbxref_rs
        = $row->feature_cvterm_dbxrefs->search_related( 'dbxref', {} );
    if ($dbxref_rs) {
        return [ map { $_->accession } $dbxref_rs->all ];
    }
}

sub get_qualifiers {
    my ( $self, $rs ) = @_;
    my @qual;
    push @qual, GOBO::Node->new( id => $_->value )
        for $rs->search( { 'type.name' => $self->qual_term } );
    return @qual;

}

sub get_with_column {
    my ( $self, $rs ) = @_;
    return [ map { GOBO::Node->new( id => $_->value ) }
            $rs->search( { 'type.name' => $self->with_term } ) ];
}

sub get_source_column {
    my ( $self, $rs ) = @_;
    return $rs->search( { 'type.name' => $self->source_term }, { rows => 1 } )
        ->single->value;
}

sub get_date_column {
    my ( $self, $rs ) = @_;
    return $rs->search( { 'type.name' => $self->date_term }, { rows => 1 } )
        ->single->value;
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Dump GAF2.0 file from chado database

