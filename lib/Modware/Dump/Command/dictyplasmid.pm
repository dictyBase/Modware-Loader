
use strict;

package Modware::Dump::Command::dictyplasmid;

use Modware::Legacy::Schema;
use Moose;
use namespace::autoclean;

extends qw/Modware::Dump::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Plasmid';

has data => (
    is      => 'rw',
    isa     => 'Str',
    default => 'all'
);

sub execute {
    my ($self) = @_;

    my $io;
    my @data;
    if ( $self->data ne 'all' ) {
        @data = split( /,/, $self->data );
    }
    else {
        @data = (
            "plasmid",      "inventory", "genbank", "phenotype",
            "publications", "genes"
        );
    }

    $self->dual_logger->info(
        "Data for {@data} will be exported to " . $self->output_dir );

    foreach my $f (@data) {
        my $file_obj
            = IO::File->new( $self->output_dir . "/plasmid_" . $f . ".txt",
            'w' );
        $io->{$f} = $file_obj;
    }

    my $plasmid_rs = $self->legacy_schema->resultset('Plasmid')->search(
        {},
        {   select =>
                [qw/id name description pubmedid genbank_accession_number/],
            cache => 1
        }
    );

    while ( my $plasmid = $plasmid_rs->next ) {

        my $plasmid_id = $plasmid->id;

        if ( exists $io->{plasmid} ) {
            $io->{plasmid}->write( $plasmid_id . "\t"
                    . $plasmid->name . "\t"
                    . $plasmid->description
                    . "\n" );
        }

        if ( exists $io->{publications} ) {
            my $pmid = $plasmid->pubmedid;
            if ($pmid) {
                $pmid = $self->trim($pmid);
                my @pmids;
                if ( $pmid =~ /,/ ) {
                    @pmids = split( /,/, $pmid );
                }
                else {
                    $pmids[0] = $pmid;
                }
                foreach my $pmid_ (@pmids) {
                    $io->{publications}->write(
                        $plasmid_id . "\t" . $self->trim($pmid_) . "\n" )
                        if $pmid_;
                }
            }
        }

        if ( exists $io->{inventory} ) {
            my $plasmid_invent_rs
                = $self->find_plasmid_inventory($plasmid_id);
            if ($plasmid_invent_rs) {
                while ( my $plasmid_invent = $plasmid_invent_rs->next ) {
                    $io->{inventory}->write( $plasmid_id . "\t"
                            . $plasmid_invent->location . "\t"
                            . $plasmid_invent->color . "\t"
                            . $plasmid_invent->stored_as . "\t"
                            . $plasmid_invent->storage_date
                            . "\n" )
                        if $plasmid_invent->location
                        and $plasmid_invent->color;
                }
            }
        }

        if ( exists $io->{genbank} ) {
            $io->{genbank}->write( $plasmid_id . "\t"
                    . $plasmid->genbank_accession_number
                    . "\n" )
                if $plasmid->genbank_accession_number;
        }

        if ( exists $io->{genes} ) {
            my $plasmid_gene_rs
                = $self->legacy_schema->resultset('PlasmidGeneLink')
                ->search( { plasmid_id => $plasmid->id }, { cache => 1 } );
            while ( my $plasmid_gene = $plasmid_gene_rs->next ) {
                my $gene_id
                    = $self->find_gene_id( $plasmid_gene->feature_id );
                $io->{genes}->write( $plasmid_id . "\t" . $gene_id . "\n" );
            }
        }

    }
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;

    #$s =~ s/[[:punct:]]//g;
    return $s;
}

1;

__END__

=head1 NAME

Modware::Dump::Command::dictyplasmid - Dump data for dicty plasmids 

=head1 VERSION

version 0.0.1

=head1 SYNOPSIS

	perl modware-dump dictyplasmid -c config.yaml  

	perl modware-dump dictyplasmid -c config.yaml --data inventory,genotype,phenotype --format <text|json> 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION



=cut
