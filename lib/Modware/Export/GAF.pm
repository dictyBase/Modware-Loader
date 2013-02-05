
use strict;

package Modware::Export::GAF;

use Data::Dumper;
use namespace::autoclean;
use Moose;
use Try::Tiny;
use IO::File;
use File::Spec::Functions;
use Time::Piece;
use Moose::Util qw/ensure_all_roles/;

extends qw/Modware::Export::Command/;

#with 'Modware::Exporter::Role::GAF::WithDataStash';

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

has 'skip_file' => (
    is      => 'rw',
    isa     => 'Str',
    trigger => sub {
        my ( $self, $file ) = @_;
        $self->meta->make_mutable;
        ensure_all_roles( $self, 'Modware::Role::Command::Export::FilterId' );
        $self->meta->make_immutable;
        $self->init_resource($file);
        $self->do_skip(1);
    },
    documentation =>
        'Text file with list of ID(one per line) that will be skipped from dumping'
);

has 'do_skip' =>
    ( is => 'rw', isa => 'Bool', default => 0, traits => [qw/NoGetopt/] );

has 'header' => (
    is      => 'rw',
    isa     => 'Str',
    default => sub {
        my ($self) = @_;
        return
              "!gaf-version: 2.0\n!"
            . Time::Piece->new->mdy('/') . "\n!"
            . $self->source_database . "("
            . $self->source_url . ")\n";
    },
    documentation => 'Header for GAF'
);

has 'aspect' => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef',
    default => sub {
        {   molecular_function => 'F',
            biological_process => 'P',
            cellular_component => 'C'
        };
    },
    handles => { get_aspect_abbr => 'get' },
);

sub execute {
    my ($self) = @_;
    my $schema = $self->chado;
    my $log    = $self->dual_logger;

    print $self->header;

    my $base_query = {
        'cvterm.is_obsolete ' => 0,
        'cv.name'             => {
            -in => [
                qw/molecular_function biological_process
                    cellular_component/
            ]
        },
        'organism.common_name' => $self->common_name,
    };

    if ( $self->include_obsolete ) {
        delete $base_query->{' cvterm . is_obsolete '};
    }

    my $assoc_rs = $schema->resultset('Sequence::FeatureCvterm')->search(
        $base_query,
        {   join => [
                { 'cvterm'  => 'cv' },
                { 'feature' => 'organism' },
                { 'feature' => 'dbxref' }
            ],
            prefetch => 'pub',
            cache    => 1,
        }
    );

    if ( $self->sample_run ) {
        $assoc_rs = $assoc_rs->search( {}, { rows => 5000 } );
    }

    $log->info( 'Processing ', $assoc_rs->count, ' entries' );

    my $io = IO::File->new( $self->output, 'w' );
    $io->write( $self->header );

    my $increment = 1;
    while ( my $assoc = $assoc_rs->next ) {

        my $feat = $assoc->feature;

        if ( $self->do_skip ) {
            next if $self->has_skip_id( $feat->dbxref->accession );
        }

        my $cvterm = $assoc->cvterm;

        my $fcvprop_rs = $assoc->feature_cvtermprops->search(
            { 'cv.name' => $self->gafcv },
            { join      => [ { 'type' => 'cv' } ] }
        );

        my $evidence_rs = $assoc->feature_cvtermprops->search_related(
            'type',
            { 'cv.name' => { -like => 'evidence_code%' } },
            { join      => 'cv' }
            )->search_related(
            'cvtermsynonyms',
            {   'type_2.name' => { -in => [qw/EXACT RELATED BROAD/] },
                'cv_2.name'   => 'synonym_type'
            },
            { join => { 'type' => 'cv' } }
            );

        my $qualifier_value = $self->get_qualifiers($fcvprop_rs);
        my $with_value      = $self->get_with_column($fcvprop_rs);

        my $gaf_row = "dictyBase" . "\t";

        print $feat->dbxref->accession . "\t";
        $gaf_row = $gaf_row . $feat->dbxref->accession . "\t";
        $gaf_row = $gaf_row . $feat->uniquename . "\t";

        if ( $qualifier_value->count > 0 ) {
            $gaf_row = $gaf_row . $qualifier_value->single->value . "\t";
        }
        else {
            $gaf_row = $gaf_row . "\t";
        }
        $gaf_row
            = $gaf_row
            . $self->go_namespace . ":"
            . $cvterm->dbxref->accession . "\t";
        $gaf_row = $gaf_row . $self->get_provenance($assoc) . "\t";

        my $evidence_code;
        if ( $evidence_rs->count > 1 ) {
            while ( my $ev = $evidence_rs->next ) {
                next if length( $ev->get_column('synonym_') ) > 3;
                $evidence_code = $ev->get_column('synonym_');
            }
        }
        else {
            $evidence_code = $evidence_rs->get_column('synonym_')->first;
        }
        $gaf_row = $gaf_row . $evidence_code . "\t";
        if ( $with_value->count > 0 ) {
            if ( $with_value->single->value ne 'With:Not_supplied' ) {
                $gaf_row = $gaf_row . $with_value->single->value;
            }

            #if ( $self->has_xrefs( $assoc->feature_cvterm_id ) ) {
            my $xrefs = $self->get_xrefs($assoc);
            if ($xrefs) {
                $gaf_row = $gaf_row . "|" . $xrefs;
                print $xrefs. "\t";
            }
        }
        $gaf_row = $gaf_row . "\t";

        $gaf_row
            = $gaf_row . $self->get_aspect_abbr( $cvterm->cv->name ) . "\t";

        my $desc = $self->get_description($feat);
        if ($desc) {
            $gaf_row = $gaf_row . $desc;
        }
        $gaf_row = $gaf_row . "\t";
        my $syn = $self->get_synonyms($feat);
        if ($syn) {
            $gaf_row = $gaf_row . $syn;
        }
        $gaf_row = $gaf_row . "\t";
        $gaf_row = $gaf_row . $feat->type->name . "\t";

        $gaf_row
            = $gaf_row
            . $self->taxon_namespace . ":"
            . $self->taxon_id . "\t";
        $gaf_row = $gaf_row . $self->get_date_column($fcvprop_rs) . "\t";
        $gaf_row = $gaf_row . $self->get_source_column($fcvprop_rs) . "\t";

        print "\n";

        #print $gaf_row. "\n";
        $io->write( $gaf_row . "\n" );

    }
    $self->inc_process;
}

sub feat2gene {
    return;
}

sub get_description {
    return;
}

sub get_synonyms {
    my ( $self, $feat ) = @_;
    my $syn_rs
        = $feat->feature_synonyms->search_related( 'alternate_names', {} );
    my @syn;
    while ( my $row = $syn_rs->next ) {
        push @syn, $row->name;
    }
    if (@syn) {
        return $syn[0] if @syn == 1;
        return join( "|", @syn );
    }
}

sub get_provenance {
    my ( $self, $row ) = @_;
    $self->pub->pubplace . ':' . $row->pub->uniquename;
}

sub get_xrefs {
    my ( $self, $row ) = @_;
    my $dbxref_rs
        = $row->feature_cvterm_dbxrefs->search_related( 'dbxref', {},
        { join => 'db', select => [qw/accession db.name/] } );
    my @xrefs;
    if ( $dbxref_rs->count > 0 ) {
        while ( my $xref = $dbxref_rs->next ) {

            #return [ map { $_->db->name => $_->accession } $dbxref_rs->all ];
            push @xrefs, $xref->db->name . ":" . $xref->accession;
        }
        if (@xrefs) {
            return $xrefs[0] if @xrefs == 1;
            return join( "|", @xrefs );
        }
    }
    return;
}

sub get_qualifiers {
    my ( $self, $rs ) = @_;
    return $rs->search( { 'type.name' => $self->qual_term } );
}

sub get_with_column {
    my ( $self, $rs ) = @_;
    return $rs->search( { 'type.name' => $self->with_term } );
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

