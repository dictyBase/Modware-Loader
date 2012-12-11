
use autodie;
use strict;
use warnings;

package Modware::Load::Command::ebiGaf2dictyChado;

use Bio::Chado::Schema;
use IO::String;
use Moose;
use namespace::autoclean;

extends qw/Modware::Load::Chado/;

has 'prune' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    lazy          => 1,
    documentation => 'Delete all annotations before loading, default is OFF'
);

has 'print_gaf' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    lazy          => 1,
    documentation => 'Print GAF retrieved from EBI per gene ID'
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;
    $logger->info( "Loading config from " . $self->configfile );
    $logger->info( ref($self) );
    my $schema = $self->schema;
    if ( $self->prune ) {
        $logger->warn('Pruning all annotations.');
        my $prune_count
            = $schema->resultset('Sequence::FeatureCvterm')->search()->count;
        $schema->txn_do(
            sub { $schema->resultset('Sequence::FeatureCvterm')->delete_all }
        );
        $logger->info(
            "Done! with pruning. " . $prune_count . " records deleted." );
    }

    my $gaf_manager = GAFManager->new;
    $gaf_manager->schema($schema);
    $logger->info('Retrieving gene IDs from dictyBase');
    my $gene_rs = $gaf_manager->get_gene_ids();

    if ( $gene_rs->count == 0 ) {
        $logger->error('NO gene IDs retrieved');
        exit;
    }
    else {
        $logger->info( $gene_rs->count . " gene IDs retrieved" );
    }
    my $ebi_query = EBIQuery->new;
    while ( my $gene = $gene_rs->next ) {

        my $gaf         = $ebi_query->query_ebi( $gene->dbxref->accession );
        my @annotations = $gaf_manager->parse($gaf);

        #sleep 0.75;

        foreach my $anno (@annotations) {

            if ( $self->print_gaf ) {
                $anno->print;
            }
            my $db_val = $anno->db_ref;
            my $go_val = $anno->go_id;
            $db_val =~ s/^PMID://x;
            $go_val =~ s/^GO://x;
            $anno->db_ref($db_val);
            $anno->go_id($go_val);

            my $cvterm_rs
                = $schema->resultset('Cv::Cvterm')
                ->search( { 'dbxref.accession' => $anno->go_id },
                { join => [qw/dbxref/], select => [qw/cvterm_id/] } );

            my $evterm_rs = $schema->resultset('Cv::Cvterm')->search(
                {   'cv.name' => { -like => 'evidence_code%' },
                    'cvtermsynonyms.synonym_' => $anno->evidence_code,
                },
                {   join   => [qw/cv cvtermsynonyms/],
                    select => [qw/cvterm_id/]
                },
            );

            if ( $anno->db_ref eq '' ) {
                $logger->error( 'No PubID ('
                        . $anno->db_ref
                        . ') for GO:'
                        . $anno->go_id );
                next;
            }
            my $pub_rs
                = $schema->resultset('Pub::Pub')
                ->search( { uniquename => $anno->db_ref },
                { select => 'pub_id' } );

            if ( $cvterm_rs->count == 0 ) {
                $logger->error( "GO:"
                        . $anno->go_id
                        . " does not exist; associated with "
                        . $gene->dbxref->accession . " ("
                        . $gene->uniquename
                        . ")" );
                next;
            }

            $self->schema->txn_do(
                sub {
                    if ( $pub_rs->count > 0 ) {
                        my $anno_check
                            = $self->find( $gene->feature_id,
                            $cvterm_rs->first->cvterm_id,
                            $pub_rs->first->pub_id );
                        my $rank = 0;
                        if ($anno_check) {
                            $rank = $anno_check->rank + 1;
                        }
                        my $fcvt
                            = $schema->resultset('Sequence::FeatureCvterm')
                            ->find_or_create(
                            {   feature_id => $gene->feature_id,
                                cvterm_id  => $cvterm_rs->first->cvterm_id,
                                pub_id     => $pub_rs->first->pub_id,
                                rank       => $rank
                            }
                            );

                        $fcvt->create_related(
                            'feature_cvtermprops',
                            {   type_id => $evterm_rs->first->cvterm_id,
                                value   => 1,
                                rank    => $rank
                            }
                        );

                        if ( $anno->qualifier ne '' ) {
                            $fcvt->create_related(
                                'feature_cvtermprops',
                                {   type_id => $gaf_manager->cvterm_qualifier,
                                    value   => $anno->qualifier,
                                    rank    => $rank
                                }
                            );
                        }

                        print $gene->dbxref->accession . "\t"
                            . $fcvt->feature_id . "\t"
                            . $fcvt->feature_cvterm_id . "\t"
                            . $anno->evidence_code . "\t"
                            . $anno->with_from . "\t"
                            . $gaf_manager->cvterm_date . "\t"
                            . $anno->date . "\t"
                            . $anno->assigned_by . "\t"
                            . $rank . "\n";

                        if ( $anno->date ne '' ) {
                            $fcvt->create_related(
                                'feature_cvtermprops',
                                {   type_id => $gaf_manager->cvterm_date,
                                    value   => $anno->date,
                                    rank    => $rank
                                }
                            );
                        }

                        if ( $anno->with_from ne '' ) {
                            $fcvt->create_related(
                                'feature_cvtermprops',
                                {   type_id => $gaf_manager->cvterm_with_from,
                                    value   => $anno->with_from,
                                    rank    => $rank
                                }
                            );
                        }

                        if ( $anno->assigned_by ne '' ) {
                            $fcvt->create_related(
                                'feature_cvtermprops',
                                {   type_id =>
                                        $gaf_manager->cvterm_assigned_by,
                                    value => $anno->assigned_by,
                                    rank  => $rank
                                }
                            );
                        }

                    }
                }
            );
        }
    }
}

sub find {
    my ( $self, $feature, $cvterm, $pub ) = @_;
    my $anno_check
        = $self->schema->resultset('Sequence::FeatureCvterm')
        ->search(
        { feature_id => $feature, cvterm_id => $cvterm, pub_id => $pub },
        { order_by => { -desc => 'rank' } } )->first;
    return $anno_check;
}

1;

package EBIQuery;

use LWP::UserAgent;
use Moose;
use MooseX::Attribute::Dependent;

has 'ebi_base_url' => (
    is      => 'rw',
    isa     => 'Str',
    default => sub {
        my ($self) = @_;
        'http://www.ebi.ac.uk/QuickGO/GAnnotation?format='
            . $self->format
            . '&ref=PMID:*&db='
            . $self->db
            . '&protein=';
    },
    lazy       => 1,
    dependency => All [ 'format', 'db' ]
);

has 'format' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'gaf',
    lazy    => 1
);

has 'db' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'dictyBase',
    lazy    => 1
);

has 'ua' => (
    is      => 'ro',
    isa     => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
    lazy    => 1
);

sub query_ebi {
    my ( $self, $gene_id ) = @_;
    my $response = $self->ua->get( $self->ebi_base_url . $gene_id );
    $response->is_success || die "NO GAF retrieved from EBI";
    return $response->decoded_content;
}

1;

package GAFManager;

use Moose;
use MooseX::Attribute::Dependent;

has 'schema' => (
    is  => 'rw',
    isa => 'Bio::Chado::Schema',
);

has 'cvterm_date' => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $date_rs = $self->schema->resultset('Cv::Cvterm')
            ->search( { name => 'date' } );
        return $date_rs->first->cvterm_id;
    },
    lazy       => 1,
    dependency => All ['schema']
);

has 'cvterm_with_from' => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $with_rs = $self->schema->resultset('Cv::Cvterm')
            ->search( { name => 'with' } );
        return $with_rs->first->cvterm_id;
    },
    lazy       => 1,
    dependency => All ['schema']
);

has 'cvterm_assigned_by' => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $source_rs = $self->schema->resultset('Cv::Cvterm')
            ->search( { name => 'source' } );
        return $source_rs->first->cvterm_id;
    },
    lazy       => 1,
    dependency => All ['schema']
);

has 'cvterm_qualifier' => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $qualifier_rs = $self->schema->resultset('Cv::Cvterm')
            ->search( { name => 'qualifier' } );
        return $qualifier_rs->first->cvterm_id;
    },
    lazy       => 1,
    dependency => All ['schema']
);

sub get_gene_ids {
    my ($self) = @_;
    my $gene_rs = $self->schema->resultset('Sequence::Feature')->search(
        {   'type.name'            => 'gene',
            'organism.common_name' => 'dicty'
        },
        {   join     => [qw/type organism/],
            select   => [qw/feature_id uniquename type_id/],
            prefetch => 'dbxref',
            rows     => 500
        }
    );
    return $gene_rs;
}

sub parse {
    my ( $self, $gaf ) = @_;
    my @annotations;
    my $io = IO::String->new();
    $io->open($gaf);
    while ( my $line = $io->getline ) {
        chomp($line);
        next if $line =~ /^!/x;

        my @row_vals = split( "\t", $line );
        my $anno = Annotation->new;
        $anno->db( $row_vals[0] );
        $anno->gene_id( $row_vals[1] );
        $anno->gene_symbol( $row_vals[2] );
        $anno->qualifier( $row_vals[3] );
        $anno->go_id( $row_vals[4] );
        $anno->db_ref( $row_vals[5] );
        $anno->evidence_code( $row_vals[6] );
        $anno->with_from( $row_vals[7] );
        $anno->aspect( $row_vals[8] );
        $anno->taxon( $row_vals[12] );
        $anno->date( $row_vals[13] );
        $anno->assigned_by( $row_vals[14] );

        push( @annotations, $anno );
    }
    return @annotations;
}

1;

package Annotation;

use Moose;

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

has [
    qw/date with_from assigned_by qualifier go_id db_ref aspect gene_id gene_symbol evidence_code/
    ] => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    lazy    => 1
    );

sub print {
    my ($self) = @_;
    my $row
        = $self->db . "\t"
        . $self->gene_id . "\t"
        . $self->gene_symbol . "\t"
        . $self->qualifier . "\t"
        . $self->go_id . "\t"
        . $self->db_ref . "\t"
        . $self->evidence_code . "\t"
        . $self->with_from . "\t"
        . $self->aspect . "\t"
        . $self->taxon . "\t"
        . $self->date . "\n";
    print $row;
}

1;

__END__

=head1 NAME

C<Modware::Load::Command::ebiGaf2dictyChado> - Update dicty Chado with GAF from EBI

=head1 VERSION

version 0.0.4

=head1 SYNOPSIS
 
perl modware-load ebigaf2dictychado -c config.yaml --print_gaf

perl modware-load ebigaf2dictychado -c config.yaml --prune 

=head1 REQUIRED ARGUMENTS

-c, --configfile 		Config file with required arguments

=head1 DESCRIPTION

Prune all the existing annotations from dicty Chado. Query EBI using the web-service for annotations for each Gene ID.
Check if the link exists between feature and annotation; if yes, populate the retrieved data.

=cut
