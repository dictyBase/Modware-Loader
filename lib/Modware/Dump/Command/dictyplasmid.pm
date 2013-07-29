
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
    default => 'all',
    documentation =>
        'Option to dump all data (default) or (plasmid, inventory, genbank, publications, genes)'
);

has 'sequence' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Option to fetch sequence in Genbank format and write to file'
);

has 'email' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Email for EUtilities to retrieve GenBank sequences'
);

sub execute {
    my ($self) = @_;

    my ( $io, $stats ) = $self->_create_files();

    my $plasmid_rs = $self->legacy_schema->resultset('Plasmid')->search(
        {},
        {   select => [
                qw/id name description pubmedid genbank_accession_number internal_db_id other_references/
            ],
            cache => 1
        }
    );

    my @genbank_ids;
    my @plasmid_no_genbank;

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
            $stats->{plasmid} = $stats->{plasmid} + 1;
        }

        if ( exists $io->{publications} ) {
            my ( $pmids_ref, $non_pmids_ref )
                = $self->resolve_references( $plasmid->pubmedid,
                $plasmid->internal_db_id, $plasmid->other_references );

            my @pmids     = @$pmids_ref;
            my @non_pmids = @$non_pmids_ref;

            if (@pmids) {
                foreach my $pmid (@pmids) {
                    if ($pmid) {
                        $io->{publications}->write(
                            $dbp_id . "\t" . $self->trim($pmid) . "\n" );
                        $stats->{publications} = $stats->{publications} + 1;
                    }

                }
            }
            if (@non_pmids) {
                foreach my $non_pmid (@non_pmids) {
                    if ($non_pmid) {
                        $io->{other_refs}->write(
                            $dbp_id . "\t" . $self->trim($non_pmid) . "\n" );
                        $stats->{other_refs} = $stats->{other_refs} + 1;
                    }
                }
            }
        }

        if ( exists $io->{inventory} ) {
            my $plasmid_invent_rs
                = $self->find_plasmid_inventory( $plasmid->id );
            if ($plasmid_invent_rs) {
                while ( my $plasmid_invent = $plasmid_invent_rs->next ) {
                    my $row;
                    $row->{1} = $dbp_id;
                    if ( $plasmid_invent->location ) {
                        $row->{2} = $plasmid_invent->location;
                    }
                    else { $row->{2} = ''; }
                    if ( $plasmid_invent->color ) {
                        $row->{3} = $plasmid_invent->color;
                    }
                    else { $row->{3} = ''; }
                    if ( $plasmid_invent->stored_as ) {
                        $row->{4} = $plasmid_invent->stored_as;
                    }
                    else { $row->{4} = ''; }
                    if ( $plasmid_invent->storage_date ) {
                        $row->{5} = $plasmid_invent;
                    }
                    else { $row->{5} = ''; }

                    my $s = join "\t" => map $row->{$_} => sort { $a <=> $b }
                        keys %$row;
                    $io->{inventory}->write( $s . "\n" );
                    $stats->{inventory} = $stats->{inventory} + 1;
                }
            }
        }

        if ( exists $io->{genbank} ) {
            if ( $plasmid->genbank_accession_number ) {
                $io->{genbank}->write( $dbp_id . "\t"
                        . $plasmid->genbank_accession_number
                        . "\n" );
                push( @genbank_ids, $plasmid->genbank_accession_number );
                $stats->{genbank} = $stats->{genbank} + 1;
            }
            else {
                push( @plasmid_no_genbank, $plasmid->id );
            }
        }

        if ( exists $io->{genes} ) {
            my $plasmid_gene_rs
                = $self->legacy_schema->resultset('PlasmidGeneLink')
                ->search( { plasmid_id => $plasmid->id }, { cache => 1 } );
            while ( my $plasmid_gene = $plasmid_gene_rs->next ) {
                my $gene_id
                    = $self->find_gene_id( $plasmid_gene->feature_id );
                $io->{genes}->write( $dbp_id . "\t" . $gene_id . "\n" );
                $stats->{genes} = $stats->{genes} + 1;
            }
        }
    }
    if ( @genbank_ids and $self->sequence ) {
        $self->export_seq( @genbank_ids, @plasmid_no_genbank );
    }

    foreach my $key ( keys $stats ) {
        $self->logger->info(
            "Exported " . $stats->{$key} . " entries for " . $key );
    }
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

sub _create_files {
    my ($self) = @_;

    my $io;
    my $stats;
    my @data;
    if ( $self->data ne 'all' ) {
        @data = split( /,/, $self->data );
    }
    else {
        @data
            = ( "plasmid", "inventory", "genbank", "publications", "genes" );
    }

    $self->logger->info(
        "Data for {@data} will be exported to " . $self->output_dir );

    foreach my $f (@data) {
        my $file_obj
            = IO::File->new( $self->output_dir . "/plasmid_" . $f . ".txt",
            'w' );
        $io->{$f}    = $file_obj;
        $stats->{$f} = 0;
        if ( $f eq 'publications' ) {
            my $f_ = "other_refs";
            my $file_obj_
                = IO::File->new(
                $self->output_dir . "/plasmid_publications_no_pubmed.txt",
                'w' );
            $io->{$f_}    = $file_obj_;
            $stats->{$f_} = 0;
        }

        #if ( $f eq 'genbank' and $self->sequence ) {
        #    $self->email( );
        #}
    }
    return ( $io, $stats );
}

1;

__END__

=head1 NAME

Modware::Dump::Command::dictyplasmid - Dump data for dicty plasmids 

=head1 VERSION

version 0.0.1

=head1 SYNOPSIS

	perl modware-dump dictyplasmid -c config.yaml --sequence_file 

	perl modware-dump dictyplasmid -c config.yaml --data inventory,genbank,genes --format <text|json> 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION



=cut
