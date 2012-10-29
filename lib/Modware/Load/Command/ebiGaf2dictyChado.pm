
package Modware::Load::Command::ebiGaf2dictyChado;

use strict;

use Bio::Chado::Schema;
use IO::String;
use Moose;
use namespace::autoclean;

extends qw/Modware::Load::Chado/;

has '_ebi_base_url' => (
    is      => 'ro',
    isa     => 'Str',
    default => 'http://www.ebi.ac.uk/QuickGO/GAnnotation?format=gaf&protein='
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
    documentation => 'Delete all annotations before loading, default is False'
);

sub execute {
    my ($self) = @_;

    my $logger = $self->logger;
    $logger->info( "Loading config from " . $self->configfile );
    my $schema = $self->schema;

    if ( $self->prune ) {
        $logger->warn('Pruning all annotations.');
        my $prune_count
            = $schema->resultset('Sequence::FeatureCvterm')->search()->count;
		#$schema->txn_do(sub { $schema->resultset('Sequence::FeatureCvterm')->delete_all });
        $logger->info(
            "Done! with pruning. " . $prune_count . " records deleted." );
    }

    $logger->info('Retrieving gene IDs from dictyBase');
    my $gene_rs = $schema->resultset('Sequence::Feature')->search(
        {   'type.name'            => 'gene',
            'organism.common_name' => 'dicty'
        },
        {   join     => [qw/type organism/],
            select   => [qw/feature_id uniquename/],
            prefetch => 'dbxref',
            rows     => 20
        }
    );
    $logger->info( $gene_rs->count . " gene IDs retrieved" );
    while ( my $gene = $gene_rs->next ) {
        my $gaf = $self->get_gaf_from_ebi( $gene->dbxref->accession );
        sleep 0.5;
        my @go_new = $self->parse_go_from_gaf($gaf);
        foreach my $go (@go_new) {
            $go =~ s/^GO://;

            #print $go. "\n";
            my $cvterm_rs = $schema->resultset('Cv::Cvterm')->search(
                { 'dbxref.accession' => $go },
                {   join   => 'dbxref',
                    select => [qw/cvterm_id/]
                }
            );
            if ( $cvterm_rs->count == 0 ) {
                $logger->error( "GO:"
                        . $go
                        . " does not exist; associated with "
                        . $gene->dbxref->accession . " ("
                        . $gene->uniquename
                        . ")" );
                next;
            }
            while ( my $cvterm = $cvterm_rs->next ) {
                print $gene->dbxref->accession . "\t"
                    . $gene->feature_id . "\t"
                    . $cvterm->cvterm_id . "\tGO:"
                    . $go . "\n";

				# Insert into feature_cvterm -> $gene->feature_id, $cvterm->cvterm_id
            }
        }
    }
}

sub parse_go_from_gaf {
    my ( $self, $gaf ) = @_;
    my @go_new;
    my $io = IO::String->new();
    $io->open($gaf);
    while ( my $line = $io->getline ) {
        chomp($line);
        next if $line =~ /^!/;
        my @row_vals = split( "\t", $line );

        #        print $row_vals[4] . "\n";
        push( @go_new, $row_vals[4] );
    }
    return @go_new;
}

sub get_gaf_from_ebi {
    my ( $self, $gene_id ) = @_;
    my $response
        = $self->_ua->get( $self->_ebi_base_url . $gene_id )->decoded_content;
    return $response;
}

1;

=head1 NAME

Modware::Load::Command::ebiGaf2dictyChado - Update dicty Chado with GAF from EBI

=head1 SYNOPSIS
 
=head1 REQUIRED ARGUMENTS

=head1 OPTIONS

=head1 DESCRIPTION

Prune all the existing annotations from dicty Chado. Query EBI using the web-service for annotations for each Gene ID.
Check if the link exists between feature and annotation; if yes, populate the retrieved data.

=over
