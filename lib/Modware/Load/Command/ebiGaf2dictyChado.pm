
package Modware::Load::Command::ebiGaf2dictyChado;

use strict;

use autodie;
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

    my $gafU = GAFUpdater->new;
    $logger->info( ref($gafU) );
    $gafU->schema($schema);
    my $gene_rs = $gafU->get_gene_ids();
    $logger->info('Retrieving gene IDs from dictyBase');

    if ( $gene_rs->count == 0 ) {
        $logger->error('NO gene IDs retrieved');
        exit;
    }
    else {
        $logger->info( $gene_rs->count . " gene IDs retrieved" );
    }
    while ( my $gene = $gene_rs->next ) {
        my @annotations = $gafU->query_ebi( $gene->dbxref->accession );
        sleep 0.75;

        #my @gaf_rows = $self->parse_gaf($gaf);
        foreach my $anno (@annotations) {

            $anno->db_ref =~ s/^PMID://x;
            $anno->go_id  =~ s/^GO://x;

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

            my $qualifier_rs = $schema->resultset('Cv::Cvterm')
                ->search( { name => 'qualifier' } );

            my $date_rs = $schema->resultset('Cv::Cvterm')
                ->search( { name => 'date' } );

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
                                rank    => 0
                            }
                        );

                        if ( $anno->qualifier ne '' ) {
                            $fcvt->create_related(
                                'feature_cvtermprops',
                                {   type_id =>
                                        $qualifier_rs->first->cvterm_id,
                                    value => $anno->qualifier,
                                    rank  => $rank
                                }
                            );
                        }
   #
   #                        if ( $gaf_row->{date} ne '' ) {
   #                            $fcvt->create_related(
   #                                'feature_cvtermprops',
   #                                {   type_id => $date_rs->first->cvterm_id,
   #                                    value   => $gaf_row->{date},
   #                                    rank    => $rank
   #                                }
   #                            );
   #                        }
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
        { feature_id => $feature, cvterm_id => $cvterm, pub_id => $pub } )
        ->first;
    return $anno_check;
}

sub parse_gaf {
    my ( $self, $gaf ) = @_;
    my @gaf_rows;
    my $io = IO::String->new();
    $io->open($gaf);
    while ( my $line = $io->getline ) {
        chomp($line);
        next if $line =~ /^!/x;
        if ( $self->print_gaf ) {
            print $line. "\n";
        }
        my @row_vals = split( "\t", $line );
        my $gaf_hash = {
            qualifier     => $row_vals[3],
            go_id         => $row_vals[4],
            ref           => $row_vals[5],
            evidence_code => $row_vals[6],
            aspect        => $row_vals[8],
            date          => $row_vals[13]
        };
        push( @gaf_rows, $gaf_hash );
    }
    return @gaf_rows;
}

1;

package GAFUpdater;

use strict;
use warnings;

use Moose;

has 'schema' => (
    is  => 'rw',
    isa => 'Bio::Chado::Schema',
);

has 'ebi_base_url' => (
    is  => 'ro',
    isa => 'Str',
    default =>
        'http://www.ebi.ac.uk/QuickGO/GAnnotation?format=gaf&ref=PMID:*&db=dictyBase&protein=',
    lazy => 1
);

has 'ua' => (
    is      => 'ro',
    isa     => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
    lazy    => 1
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
            rows     => 50
        }
    );
    return $gene_rs;
}

sub query_ebi {
    my ( $self, $gene_id ) = @_;
    my $response
        = $self->ua->get( $self->ebi_base_url . $gene_id )->decoded_content;
    return $self->parse($response);
}

sub parse {
    my ( $self, $gaf ) = @_;
    my @annotations;
    my $io = IO::String->new();
    $io->open($gaf);
    while ( my $line = $io->getline ) {
        chomp($line);
        next if $line =~ /^!/x;

        #if ( $self->print_gaf ) {
        #    print $line. "\n";
        #}
        my @row_vals = split( "\t", $line );
        my $anno = Annotation->new;
        $anno->qualifier( $row_vals[3] );
        $anno->go_id( $row_vals[4] );
        $anno->db_ref( $row_vals[5] );
        $anno->evidence_code( $row_vals[6] );
        $anno->aspect( $row_vals[8] );
        $anno->date( $row_vals[13] );

        push( @annotations, $anno );
    }
    return @annotations;
}

1;

package Annotation;

use strict;
use warnings;

use Moose;

has 'go_id' => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    lazy    => 1
);

has 'qualifier' => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    lazy    => 1
);

has 'with_from' => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    lazy    => 1
);

has 'date' => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    lazy    => 1
);

has 'evidence_code' => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    lazy    => 1
);

has [qw/db_ref aspect db gene_id gene_symbol/] => (
    is      => 'rw',
    isa     => 'Str',
    default => '',
    lazy    => 1
);

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
