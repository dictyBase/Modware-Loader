
package Modware::Dump::Command::dictyplasmid;

use autodie;
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

has 'seq_data_dir' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'Folder with raw plasmid sequences with sub-folders fasta/genbank'
);

sub execute {
    my ($self) = @_;

    my ( $io, $stats ) = $self->_create_files();

    my $plasmid_rs = $self->legacy_schema->resultset('Plasmid')
        ->search( {}, { cache => 1 } );
    $plasmid_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');

    my $gb_dbp_hash;
    my @plasmid_no_genbank;

    while ( my $plasmid = $plasmid_rs->next ) {

        my $dbp_id = sprintf( "DBP%07d", $plasmid->{id} );

        if ( exists $io->{plasmid} ) {
            my $name = $self->trim( $plasmid->{name} ) if $plasmid->{name};
            my $desc = $self->trim( $plasmid->{description} )
                if $plasmid->{description};
            my $s = sprintf "%s\t%s\t%s\n", $dbp_id, $name, $desc;
            $io->{plasmid}->write($s);
            $stats->{plasmid} = $stats->{plasmid} + 1;
        }

        if ( exists $io->{publications} ) {
            my ( $pmids_ref, $non_pmids_ref ) = $self->resolve_references(
                $plasmid->{pubmedid},
                $plasmid->{internal_db_id},
                $plasmid->{other_references}
            );

            my @pmids     = @{$pmids_ref};
            my @non_pmids = @{$non_pmids_ref};

            if (@pmids) {
                my @data;
                for my $pmid (@pmids) {
                    my $s = sprintf "%s\t%s", $dbp_id, $self->trim($pmid);
                    push @data, $s;
                    $stats->{publications} = $stats->{publications} + 1;
                }
                my $outstr = join( "\n", @data );
                $io->{publications}->write( $outstr . "\n" );
            }
            if (@non_pmids) {
                my @data;
                for my $non_pmid (@non_pmids) {
                    if ($non_pmid) {
                        my $s = sprintf "%s\t%s", $dbp_id,
                            $self->trim($non_pmid);
                        push @data, $s;
                        $stats->{other_refs} = $stats->{other_refs} + 1;
                    }
                }
                my $outstr = join( "\n", @data );
                $io->{other_refs}->write( $outstr . "\n" ) if $outstr;
            }
        }

        if ( exists $io->{inventory} ) {
            my $plasmid_invent_rs
                = $self->find_plasmid_inventory( $plasmid->{id} );
            if ($plasmid_invent_rs) {
                $plasmid_invent_rs->result_class(
                    'DBIx::Class::ResultClass::HashRefInflator');
                while ( my $plasmid_invent = $plasmid_invent_rs->next ) {
                    my @row;
                    push @row, $dbp_id;

                    if ( $plasmid_invent->{location} ) {
                        push @row, $plasmid_invent->{location};
                    }
                    else {
                        push @row, '';
                    }

                    my $color
                        = $self->trim( ucfirst( $plasmid_invent->{color} ) );
                    if ( $color =~ /[A-Z]{2,8}/ ) {
                        push @row, $color;
                    }
                    else {
                        push @row, '';
                    }

                    my $stored_as = $plasmid_invent->{stored_as};
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

                    if ( $plasmid_invent->{storage_date} ) {
                        push @row, $plasmid_invent->{storage_date};
                    }
                    else {
                        push @row, '';
                    }

                    # No private comments for plasmid inventory

                    my $public_comment
                        = $plasmid_invent->{other_comments_and_feedback};
                    if ($public_comment) {
                        push @row, $self->trim($public_comment);
                    }
                    else {
                        push @row, ' ';
                    }

                    my $s = join( "\t", @row );
                    $io->{inventory}->write( $s . "\n" );
                    $stats->{inventory} = $stats->{inventory} + 1;
                }
            }
        }

        if ( exists $io->{genbank} ) {
            if ( $plasmid->{genbank_accession_number} ) {
                $io->{genbank}->write( $dbp_id . "\t"
                        . $plasmid->{genbank_accession_number}
                        . "\n" );
                $gb_dbp_hash->{ $plasmid->{genbank_accession_number} }
                    = $dbp_id;
                $stats->{genbank} = $stats->{genbank} + 1;
            }
            else {
                push @plasmid_no_genbank, $plasmid->{id};
            }
        }

        if ( exists $io->{genes} ) {
            my $plasmid_gene_rs
                = $self->legacy_schema->resultset('PlasmidGeneLink')
                ->search( { plasmid_id => $plasmid->{id} }, { cache => 1 } );
            while ( my $plasmid_gene = $plasmid_gene_rs->next ) {
                my $gene_id
                    = $self->find_gene_id( $plasmid_gene->feature_id );
                $io->{genes}->write( $dbp_id . "\t" . $gene_id . "\n" );
                $stats->{genes} = $stats->{genes} + 1;
            }
        }

        if ( exists $io->{props} ) {
            my @data;
            if ( $plasmid->{depositor} ) {
                my $s = sprintf "%s\tdepositor\t%s", $dbp_id,
                    $self->trim( $plasmid->{depositor} );
                push @data, $s;
                $stats->{props} = $stats->{props} + 1;
            }
            if ( $plasmid->{synonymn} ) {
                my @syns;
                my $synonym = $self->trim( $plasmid->{synonymn} );
                if ( $synonym =~ /,/ ) {
                    @syns = split( /,/, $synonym );
                }
                else {
                    $syns[0] = $synonym;
                }
                for my $syn (@syns) {
                    my $s = sprintf "%s\tsynonym\t%s", $dbp_id,
                        $self->trim($syn);
                    push @data, $s;
                    $stats->{props} = $stats->{props} + 1;
                }
            }
            if ( $plasmid->{keywords} ) {
                my @keywords;
                if ( $plasmid->{keywords} ) {
                    @keywords = split( /[,]/, $plasmid->{keywords} );
                }
                else {
                    $keywords[0] = $plasmid->{keywords};
                }
                for my $keyword (@keywords) {
                    my $s = sprintf "%s\tkeyword\t%s", $dbp_id,
                        $self->trim($keyword);
                    push @data, $s;
                    $stats->{props} = $stats->{props} + 1;
                }
            }
            my $outstr = join( "\n", @data );
            $io->{props}->write( $outstr . "\n" ) if $outstr;
        }

    }

    if ( $gb_dbp_hash and $self->seq_data_dir ) {
        $self->export_seq( $gb_dbp_hash, $self->seq_data_dir );
    }

    for my $key ( keys $stats ) {
        $self->logger->info(
            "Exported " . $stats->{$key} . " entries for " . $key );
    }
    return;
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/[\n\r]/ /g;
    $s =~ s/[\t]/ /g;
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
        my $outfile = "plasmid_" . $data_type . ".tsv";
        my $file_obj
            = IO::File->new( catfile( $self->output_dir, $outfile ), 'w' );
        $io->{$data_type}    = $file_obj;
        $stats->{$data_type} = 0;
        if ( $data_type eq 'publications' ) {
            my $data_type_ = "other_refs";
            my $outfile_   = "plasmid_publications_no_pubmed.tsv";
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

	perl modware-dump dictyplasmid -c config.yaml --seq_data_dir <plasmid-raw-seq-folder>

	perl modware-dump dictyplasmid -c config.yaml --data inventory --data genbank --data genes 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION


=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT 
=cut
