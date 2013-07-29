
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
        @data
            = ( "plasmid", "inventory", "genbank", "publications", "genes" );
    }

    $self->dual_logger->info(
        "Data for {@data} will be exported to " . $self->output_dir );

    foreach my $f (@data) {
        my $file_obj
            = IO::File->new( $self->output_dir . "/plasmid_" . $f . ".txt",
            'w' );
        $io->{$f} = $file_obj;
        if ( $f eq 'publications' ) {
            my $f_ = "other_refs";
            my $file_obj_
                = IO::File->new(
                $self->output_dir . "/plasmid_publications_no_pubmed.txt",
                'w' );
            $io->{$f_} = $file_obj_;
        }
    }

    my $plasmid_rs = $self->legacy_schema->resultset('Plasmid')->search(
        {},
        {   select => [
                qw/id name description pubmedid genbank_accession_number internal_db_id other_references/
            ],
            cache => 1
        }
    );

    while ( my $plasmid = $plasmid_rs->next ) {

        my $dbp_id = sprintf( "DBP%07d", $plasmid->id );

        if ( exists $io->{plasmid} ) {
            my $name = $self->trim( $plasmid->name ) if $plasmid->name;
            my $desc = $self->trim( $plasmid->description )
                if $plasmid->description;
            $desc =~ s/\r\n/ /g;
            $io->{plasmid}->write( $dbp_id . "\t"
                    . $self->trim($name) . "\t"
                    . $self->trim($self->trim($desc))
                    . "\n" );
        }

        if ( exists $io->{publications} ) {
            my ( $pmids_ref, $non_pmids_ref )
                = $self->resolve_references( $plasmid->pubmedid,
                $plasmid->internal_db_id, $plasmid->other_references );

            my @pmids     = @$pmids_ref;
            my @non_pmids = @$non_pmids_ref;

            if (@pmids) {
                foreach my $pmid (@pmids) {
                    $io->{publications}
                        ->write( $dbp_id . "\t" . $self->trim($pmid) . "\n" )
                        if $pmid;
                }
            }
            if (@non_pmids) {
                foreach my $non_pmid (@non_pmids) {
                    $io->{other_refs}->write(
                        $dbp_id . "\t" . $self->trim($non_pmid) . "\n" )
                        if $non_pmid;
                }
            }
        }

        if ( exists $io->{inventory} ) {
            my $plasmid_invent_rs
                = $self->find_plasmid_inventory( $plasmid->id );
            if ($plasmid_invent_rs) {
                while ( my $plasmid_invent = $plasmid_invent_rs->next ) {
                    $io->{inventory}->write( $dbp_id . "\t"
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
            $io->{genbank}->write(
                $dbp_id . "\t" . $plasmid->genbank_accession_number . "\n" )
                if $plasmid->genbank_accession_number;
        }

        if ( exists $io->{genes} ) {
            my $plasmid_gene_rs
                = $self->legacy_schema->resultset('PlasmidGeneLink')
                ->search( { plasmid_id => $plasmid->id }, { cache => 1 } );
            while ( my $plasmid_gene = $plasmid_gene_rs->next ) {
                my $gene_id
                    = $self->find_gene_id( $plasmid_gene->feature_id );
                $io->{genes}->write( $dbp_id . "\t" . $gene_id . "\n" );
            }
        }

    }
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

Modware::Dump::Command::dictyplasmid - Dump data for dicty plasmids 

=head1 VERSION

version 0.0.1

=head1 SYNOPSIS

	perl modware-dump dictyplasmid -c config.yaml  

	perl modware-dump dictyplasmid -c config.yaml --data inventory,genbank,genes --format <text|json> 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION



=cut
