
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

sub execute {
    my ($self) = @_;

    print ref( $self->schema );
    my $gene_rs = $self->schema->resultset('Sequence::Feature')->search(
        {   'type.name'            => 'gene',
            'organism.common_name' => 'dicty'
        },
        {   join     => [qw/type organism/],
            select   => [qw/feature_id uniquename/],
            prefetch => 'dbxref'
        }
    );
    while ( my $gene = $gene_rs->next ) {
        my $gaf      = $self->get_gaf_from_ebi( $gene->dbxref->accession );
        my @go_new   = $self->parse_go_from_gaf($gaf);
        my @go_exist = $self->get_go_for_gene( $gene->dbxref->accession );
		#$self->compare_go( @go_new, @go_exist );
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
        print $row_vals[4] . "\n";
        push( @go_new, $row_vals[4] );
    }
    return @go_new;
}

sub get_go_for_gene {
    my ( $self, $gene_id ) = @_;
    my $go_rs = $self->schema->resultset('Sequence::Feature')->search(

    );
}

sub get_gaf_from_ebi {
    my ( $self, $gene_id ) = @_;
    my $response
        = $self->_ua->get( $self->_ebi_base_url . $gene_id )->decoded_content;
    return $response;
}

sub compare_go {

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

