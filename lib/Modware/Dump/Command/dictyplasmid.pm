
package Modware::Dump::Command::dictyplasmid;

use strict;

use File::Spec::Functions qw/catfile/;
use Modware::Legacy::Schema;
use Moose;
use namespace::autoclean;

extends qw/Modware::Dump::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Export::Plasmid';

has data => (
    is  => 'rw',
    isa => 'ArrayRef',
    default =>
        sub { [qw/plasmid inventory genbank publications genes props/] },
    documentation =>
        'Option to dump all data (default) or (plasmid, inventory, genbank, publications, genes, props)'
);

has 'genbank_file' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Option to fetch sequence in Genbank format and write to file'
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

            my @pmids     = @{$pmids_ref};
            my @non_pmids = @{$non_pmids_ref};

            if (@pmids) {
                my $outstr = '';
                for my $pmid (@pmids) {
                    if ($pmid) {
                        $outstr
                            = $outstr
                            . $dbp_id . "\t"
                            . $self->trim($pmid) . "\n";
                        $stats->{publications} = $stats->{publications} + 1;
                    }
                }
                $io->{publications}->write($outstr);
            }
            if (@non_pmids) {
                my $outstr = '';
                for my $non_pmid (@non_pmids) {
                    if ($non_pmid) {
                        $outstr
                            = $outstr
                            . $dbp_id . "\t"
                            . $self->trim($non_pmid) . "\n";
                        $stats->{other_refs} = $stats->{other_refs} + 1;
                    }
                }
                $io->{other_refs}->write($outstr);
            }
        }

        if ( exists $io->{inventory} ) {
            my $plasmid_invent_rs
                = $self->find_plasmid_inventory( $plasmid->id );
            if ($plasmid_invent_rs) {
                while ( my $plasmid_invent = $plasmid_invent_rs->next ) {
                    my @row;
                    push @row, $dbp_id;

                    if ( $plasmid_invent->location ) {
                        push @row, $plasmid_invent->location;
                    }
                    else {
                        push @row, '';
                    }

                    my $color
                        = $self->trim( ucfirst( $plasmid_invent->color ) );
                    if ( length($color) > 1 ) {
                        push @row, $color;
                    }
                    else {
                        push @row, '';
                    }

                    my $stored_as = $plasmid_invent->stored_as;
                    if ($stored_as) {
                        $stored_as =~ s/\?//g;
                        $stored_as = $self->trim($stored_as);
                        if ( length($stored_as) > 1 ) {
                            push @row, $stored_as;
                        }
                        else {
                            push @row, '';
                        }
                    }
                    else {
                        push @row, '';
                    }

                    if ( $plasmid_invent->storage_date ) {
                        push @row, $plasmid_invent->storage_date;
                    }
                    else {
                        push @row, '';
                    }

                    my $s = join( "\t", @row );
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
                push @plasmid_no_genbank, $plasmid->id;
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
            my $outstr = '';
            if ( $plasmid->depositor ) {
                $outstr
                    = $outstr
                    . $dbp_id . "\t"
                    . 'depositor' . "\t"
                    . $self->trim( $plasmid->depositor ) . "\n";
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
                for my $syn (@syns) {
                    $outstr
                        = $outstr
                        . $dbp_id . "\t"
                        . 'synonym' . "\t"
                        . $self->trim($syn) . "\n";
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
                for my $keyword (@keywords) {
                    $outstr
                        = $outstr
                        . $dbp_id . "\t"
                        . 'keyword' . "\t"
                        . $self->trim($keyword) . "\n";
                    $stats->{props} = $stats->{props} + 1;
                }
            }
            $io->{props}->write($outstr);
        }

    }

    if ( $gb_dbp_hash and $self->sequence ) {
        $self->export_seq($gb_dbp_hash);
    }

    for my $key ( keys $stats ) {
        $self->logger->info(
            "Exported " . $stats->{$key} . " entries for " . $key );
    }
    return;
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

    $self->logger->info( "Data for [@{$self->data}] will be exported to "
            . $self->output_dir );

    for my $data_type ( @{ $self->data } ) {
        my $outfile = "plasmid_" . $data_type . ".txt";
        my $file_obj
            = IO::File->new( catfile( $self->output_dir, $outfile ), 'w' );
        $io->{$data_type}    = $file_obj;
        $stats->{$data_type} = 0;
        if ( $data_type eq 'publications' ) {
            my $data_type_ = "other_refs";
            my $outfile_   = "plasmid_publications_no_pubmed.txt";
            my $file_obj_
                = IO::File->new( catfile( $self->output_dir, $outfile_ ),
                'w' );
            $io->{$data_type_}    = $file_obj_;
            $stats->{$data_type_} = 0;
        }
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

	perl modware-dump dictyplasmid -c config.yaml --data inventory --data genbank --data genes 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION


=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT 
=cut
