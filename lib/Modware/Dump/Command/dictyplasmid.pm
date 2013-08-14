
use strict;

package Modware::Dump::Command::dictyplasmid;

use Modware::Legacy::Schema;
use Moose;
use namespace::autoclean;

extends qw/Modware::Dump::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Export::Plasmid';

has data => (
    is      => 'rw',
    isa     => 'Str',
    default => 'all',
    documentation =>
        'Option to dump all data (default) or (plasmid, inventory, genbank, publications, genes, props)'
);

has 'sequence' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Option to fetch sequence in Genbank format and write to file'
);

sub execute {
    my ($self) = @_;

    my ( $io, $stats ) = $self->_create_files();

    my $plasmid_rs = $self->legacy_schema->resultset('Plasmid')->search(
        {},
        {   select => [
                qw/id name description pubmedid genbank_accession_number internal_db_id other_references depositor synonymn keywords/
            ],
            cache => 1
        }
    );

    my $gb_dbp_hash;
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
                    . $self->trim( $self->trim($desc) )
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

                    my $C = $self->trim( ucfirst( $plasmid_invent->color ) );
                    if ( length($C) > 1 ) {
                        $row->{3} = $C;
                    }
                    else { $row->{3} = '' }

                    my $SA = $plasmid_invent->stored_as;
                    if ( $SA and length($SA) > 1 ) {
                        $SA =~ s/\?//g;
                        $SA = $self->trim($SA);
                        if ( length($SA) > 1 ) {
                            $row->{4} = $SA;
                        }
                        else { $row->{4} = '' }
                    }
                    else { $row->{4} = '' }

                    if ( $plasmid_invent->storage_date ) {
                        $row->{5} = $plasmid_invent->storage_date;
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
                $gb_dbp_hash->{ $plasmid->genbank_accession_number }
                    = $dbp_id;
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

        if ( exists $io->{props} ) {
            if ( $plasmid->depositor ) {
                $io->{props}->write( $dbp_id . "\t"
                        . 'depositor' . "\t"
                        . $self->trim( $plasmid->depositor )
                        . "\n" );
                $stats->{props} = $stats->{props} + 1;
            }
            if ( $plasmid->synonymn ) {
                my @syns;
                if ( $plasmid->synonymn =~ /,/ ) {
                    @syns = split( /,/, $self->trim( $plasmid->synonymn ) );
                }
                else {
                    $syns[0] = $self->trim( $plasmid->synonymn );
                }
                foreach my $syn (@syns) {
                    $io->{props}->write( $dbp_id . "\t"
                            . 'synonym' . "\t"
                            . $self->trim($syn)
                            . "\n" );
                    $stats->{props} = $stats->{props} + 1;
                }
            }
            if ( $plasmid->keywords ) {
                my @keywords;
                if ( $plasmid->keywords ) {
                    @keywords = split( /[,;]/, $plasmid->keywords );
                }
                else {
                    $keywords[0] = $plasmid->keywords;
                }
                foreach my $keyword (@keywords) {
                    $io->{props}->write( $dbp_id . "\t"
                            . 'keyword' . "\t"
                            . $self->trim($keyword)
                            . "\n" );
                    $stats->{props} = $stats->{props} + 1;
                }
            }
        }

    }

    if ( $gb_dbp_hash and $self->sequence ) {
        $self->export_seq($gb_dbp_hash);
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
        @data = (
            "plasmid", "inventory", "genbank", "publications",
            "genes",   "props"
        );
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

	perl modware-dump dictyplasmid -c config.yaml --sequence

	perl modware-dump dictyplasmid -c config.yaml --data inventory,genbank,genes 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION



=cut
