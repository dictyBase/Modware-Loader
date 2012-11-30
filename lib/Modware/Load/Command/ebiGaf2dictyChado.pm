
package Modware::Load::Command::ebiGaf2dictyChado;

use strict;

use autodie;
use Bio::Chado::Schema;
use IO::String;
use Moose;
use namespace::autoclean;

extends qw/Modware::Load::Chado/;

has '_ebi_base_url' => (
    is  => 'ro',
    isa => 'Str',
    default =>
        'http://www.ebi.ac.uk/QuickGO/GAnnotation?format=gaf&ref=PMID:*&db=dictyBase&protein=',
    lazy => 1
);

has '_ua' => (
    is      => 'ro',
    isa     => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
    lazy    => 1
);

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

    $logger->info('Retrieving gene IDs from dictyBase');
    my $gene_rs = $schema->resultset('Sequence::Feature')->search(
        {   'type.name'            => 'gene',
            'organism.common_name' => 'dicty'
        },
        {   join     => [qw/type organism/],
            select   => [qw/feature_id uniquename type_id/],
            prefetch => 'dbxref',
            rows     => 50
        }
    );
    if ( $gene_rs->count == 0 ) {
        $logger->error('NO gene IDs retrieved');
        exit;
    }
    else {
        $logger->info( $gene_rs->count . " gene IDs retrieved" );
    }
    while ( my $gene = $gene_rs->next ) {
        my $gaf = $self->get_gaf_from_ebi( $gene->dbxref->accession );
        sleep 0.75;
        my @gaf_rows = $self->parse_gaf($gaf);
        foreach my $gaf_row (@gaf_rows) {

            $gaf_row->{ref}   =~ s/^PMID://x;
            $gaf_row->{go_id} =~ s/^GO://x;

            my $cvterm_rs = $schema->resultset('Cv::Cvterm')->search(
                { 'dbxref.accession' => $gaf_row->{go_id} },
                { join => [qw/dbxref/], select => [qw/cvterm_id/] }
            );

            my $evterm_rs = $schema->resultset('Cv::Cvterm')->search(
                {   'cv.name' => { -like => 'evidence_code%' },
                    'cvtermsynonyms.synonym_' => $gaf_row->{evidence_code},
                },
                {   join   => [qw/cv cvtermsynonyms/],
                    select => [qw/cvterm_id/]
                },
            );

#$logger->debug( $evterm_rs->count . ' Cvterm IDs for ' . $gaf_row->{evidence_code} );

            if ( $gaf_row->{ref} eq '' ) {
                $logger->error( 'No PubID ('
                        . $gaf_row->{ref}
                        . ') for GO:'
                        . $gaf_row->{go_id} );
                next;
            }
            my $pub_rs
                = $schema->resultset('Pub::Pub')
                ->search( { uniquename => $gaf_row->{ref} },
                { select => 'pub_id' } );

            if ( $cvterm_rs->count == 0 ) {
                $logger->error( "GO:"
                        . $gaf_row->{go_id}
                        . " does not exist; associated with "
                        . $gene->dbxref->accession . " ("
                        . $gene->uniquename
                        . ")" );
                next;
            }

            my $qualifier_rs = $schema->resultset('Cv::Cvterm')
                ->search( { name => 'qualifier' } );

            #$logger->info( $qualifier_rs->first->cvterm_id );
            my $date_rs = $schema->resultset('Cv::Cvterm')
                ->search( { name => 'date' } );
            $logger->info(
                $date_rs->first->cvterm_id . "\t" . $gaf_row->{date} );

            $self->schema->txn_do(
                sub {
                    $logger->debug( $gene->dbxref->accession );
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

                        if ( $gaf_row->{qualifier} ne '' ) {
                            $fcvt->create_related(
                                'feature_cvtermprops',
                                {   type_id =>
                                        $qualifier_rs->first->cvterm_id,
                                    value => $gaf_row->{qualifier},
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

sub get_gaf_from_ebi {
    my ( $self, $gene_id ) = @_;
    my $response
        = $self->_ua->get( $self->_ebi_base_url . $gene_id )->decoded_content;
    return $response;
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
