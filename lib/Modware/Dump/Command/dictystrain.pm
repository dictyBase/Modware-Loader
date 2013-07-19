
use strict;

package Modware::Dump::Command::dictystrain;

use Modware::Legacy::Schema;
use Moose;
use namespace::autoclean;

extends qw/Modware::Dump::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Strain';

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
            "strain",       "inventory", "genotype", "phenotype",
            "publications", "genes",     "characteristics"
        );
    }

    $self->dual_logger->info(
        "Data for {@data} will be exported to " . $self->output_dir );

    foreach my $f (@data) {
        my $file_obj
            = IO::File->new( $self->output_dir . "/strain_" . $f . ".txt",
            'w' );
        $io->{$f} = $file_obj;
    }

    my $strain_rs = $self->legacy_schema->resultset('StockCenter')->search(
        {},
        {   select => [
                qw/id strain_name strain_description species dbxref_id pubmedid genotype other_references internal_db_id/
            ],
            cache => 1
        }
    );

    while ( my $strain = $strain_rs->next ) {

        my $dbs_id = $self->find_dbxref_accession( $strain->dbxref_id );

        if ( exists $io->{strain} ) {
            $io->{strain}->write( $dbs_id . "\t"
                    . $strain->strain_name . "\t"
                    . $strain->species . "\t"
                    . $strain->strain_description
                    . "\n" );
        }

        if ( exists $io->{inventory} ) {
            my $strain_invent_rs = $self->find_strain_inventory($dbs_id);
            if ($strain_invent_rs) {
                while ( my $strain_invent = $strain_invent_rs->next ) {
                    $io->{inventory}->write( $dbs_id . "\t"
                            . $strain_invent->location . "\t"
                            . $strain_invent->color . "\t"
                            . $strain_invent->no_of_vials . "\t"
                            . $strain_invent->obtained_as . "\t"
                            . $strain_invent->stored_as . "\t"
                            . $strain_invent->storage_date
                            . "\n" )
                        if $strain_invent->location
                        and $strain_invent->color
                        and $strain_invent->no_of_vials;
                }
            }
        }

        if ( $io->{publications} ) {
            my @pmids = $self->resolve_references( $strain->pubmedid,
                $strain->internal_db_id, $strain->other_references );

            if (@pmids) {
                foreach my $pmid (@pmids) {
                    print $dbs_id . "\t" . $self->trim($pmid) . "\n" if $pmid;
                    $io->{publications}
                        ->write( $dbs_id . "\t" . $self->trim($pmid) . "\n" )
                        if $pmid;
                }
            }
        }

        if ( exists $io->{genotype} ) {
            if ( $strain->genotype ) {
                my $genotype = $self->trim( $strain->genotype );
                $io->{genotype}->write( $dbs_id . "\t"
                        . $strain->strain_name . "\t"
                        . $genotype
                        . "\n" );
            }
        }

        if ( exists $io->{phenotype} ) {

        }

        if ( exists $io->{genes} ) {
            my $strain_gene_rs
                = $self->legacy_schema->resultset('StrainGeneLink')
                ->search( { strain_id => $strain->id }, { cache => 1 } );
            while ( my $strain_gene = $strain_gene_rs->next ) {
                my $gene_id = $self->find_gene_id( $strain_gene->feature_id );
                $io->{genes}->write( $dbs_id . "\t" . $gene_id . "\n" );
            }
        }

        if ( exists $io->{characteristics} ) {
            my $strain_char_rs
                = $self->legacy_schema->resultset('StrainCharCvterm')
                ->search( { strain_id => $strain->id }, { cache => 1 } );
            while ( my $strain_char = $strain_char_rs->next ) {
                my $cvterm_name
                    = $self->find_cvterm_name( $strain_char->cvterm_id );
                $io->{characteristics}
                    ->write( $dbs_id . "\t" . $cvterm_name . "\n" );
            }
        }
    }
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;

    # $s =~ s/[[:punct:]]//g;
    return $s;
}

1;

__END__

=head1 NAME

Modware::Dump::Command::dictystrain - Dump data for dicty strains 

=head1 VERSION

version 0.0.1

=head1 SYNOPSIS

	perl modware-dump dictystrain -c config.yaml --output_dir <data> 

	perl modware-dump dictystrain -c config.yaml --output_dir <data> --data <inventory|publications|genotype|phenotype> --format <text|json> 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION

=cut
