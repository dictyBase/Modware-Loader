
use strict;

package Modware::Dump::Command::dictystrain;

use Data::Dumper;
use Modware::Legacy::Schema;
use Moose;
use namespace::autoclean;

extends qw/Modware::Dump::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Strain';

has data => (
    is      => 'rw',
    isa     => 'Str',
    default => 'all',
    documentation =>
        'Option to dump all data (default) or (strain, inventory, genotype, phenotype, publications, genes, characteristics)'
);

sub execute {
    my ($self) = @_;

    my $io;
	my $stats;
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
        $io->{$f}    = $file_obj;
		$stats->{$f} = 0;

        if ( $f eq 'publications' ) {
            my $f_ = "other_refs";
            my $file_obj_
                = IO::File->new(
                $self->output_dir . "/strain_publications_no_pubmed.txt",
                'w' );
            $io->{$f_} = $file_obj_;
        }
    }

    my $strain_rs = $self->legacy_schema->resultset('StockCenter')->search(
        {},
        {   select => [
                qw/id strain_name strain_description species dbxref_id pubmedid phenotype genotype other_references internal_db_id/
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
			$stats->{strain} = $stats->{strain} + 1;
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
					$stats->{inventory} = $stats->{inventory} + 1;
                }
            }
        }

        if ( $io->{publications} ) {
            my ( $pmids_ref, $non_pmids_ref )
                = $self->resolve_references( $strain->pubmedid,
                $strain->internal_db_id, $strain->other_references );

            my @pmids     = @$pmids_ref;
            my @non_pmids = @$non_pmids_ref;

            if (@pmids) {
                foreach my $pmid (@pmids) {
                    if ($pmid) {
                        $io->{publications}->write(
                            $dbs_id . "\t" . $self->trim($pmid) . "\n" );
						$stats->{publications} = $stats->{publications} + 1;
                    }
                }
            }
            if (@non_pmids) {
                foreach my $non_pmid (@non_pmids) {
                    if ($non_pmid) {
                        $io->{other_refs}->write(
                            $dbs_id . "\t" . $self->trim($non_pmid) . "\n" );
						$stats->{other_refs} = $stats->{other_refs} + 1;
                    }
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
				$stats->{genotype} = $stats->{genotype} + 1;
            }
        }

        if ( exists $io->{phenotype} ) {
            if ( $strain->phenotype ) {
                my @phenotypes = split( /[,;]/, $strain->phenotype );
                foreach my $phenotype (@phenotypes) {
                    $phenotype = $self->trim($phenotype);
                    if (   !$self->is_strain_genotype($phenotype)
                        && !$self->is_strain_characteristic($phenotype) )
                    {
                        if ($phenotype) {
                            $io->{phenotype}
                                ->write( $dbs_id . "\t" . $phenotype . "\n" );
							$stats->{phenotype} = $stats->{phenotype} + 1;
                        }
                    }
                }
            }
        }

        if ( exists $io->{genes} ) {
            my $strain_gene_rs
                = $self->legacy_schema->resultset('StrainGeneLink')
                ->search( { strain_id => $strain->id }, { cache => 1 } );
            while ( my $strain_gene = $strain_gene_rs->next ) {
                my $gene_id = $self->find_gene_id( $strain_gene->feature_id );
                $io->{genes}->write( $dbs_id . "\t" . $gene_id . "\n" );
				$stats->{genes} = $stats->{genes} + 1;
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
				$stats->{characteristics} = $stats->{characteristics} + 1;
            }
        }
    }
	$self->dual_logger->info( Dumper($stats) );
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

1;

__END__

=head1 NAME

Modware::Dump::Command::dictystrain - Dump data for dicty strains 

=head1 VERSION

version 0.0.1

=head1 SYNOPSIS

	perl modware-dump dictystrain -c config.yaml  

	perl modware-dump dictystrain -c config.yaml --data <inventory,publications,genotype,phenotype> 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION

=cut
