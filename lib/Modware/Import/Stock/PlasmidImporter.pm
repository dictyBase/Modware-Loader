
package Modware::Import::Stock::PlasmidImporter;

use strict;
use feature 'say';

use Bio::SeqIO;
use Carp;
use Digest::MD5 qw(md5_hex);
use File::Temp;
use IO::String;
use LWP::Simple qw/head/;
use Moose;
use namespace::autoclean;
use Path::Class::Dir;
use Text::CSV;

use Modware::Import::Stock::DataTransformer;

has schema => ( is => 'rw', isa => 'DBIx::Class::Schema' );
has logger => ( is => 'rw', isa => 'Log::Log4perl::Logger' );
has utils  => ( is => 'rw', isa => 'Modware::Import::Utils' );

with 'Modware::Role::Stock::Import::DataStash';

sub import_stock {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my $type_id
        = $self->find_or_create_cvterm( 'plasmid', 'dicty_stockcenter' );
    my $stockcollection_rs
        = $self->schema->resultset('Stock::Stockcollection')->find_or_create(
        {   type_id    => $type_id,
            name       => 'dicty_stockcenter',
            uniquename => $self->utils->nextval( 'stockcollection', 'DSC' )
        }
        );
    my $stockcollection_id = $stockcollection_rs->stockcollection_id;

    my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBP ID");
                next;
            }

            my $data;
            $data->{uniquename}  = $fields[0];
            $data->{name}        = $fields[1];
            $data->{description} = $self->utils->trim( $fields[2] )
                if $fields[2];
            $data->{type_id} = $type_id;
            $data->{stockcollection_stocks}
                = [ { stockcollection_id => $stockcollection_id } ];
            push @stock_data, $data;
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 3 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::Stock')->populate( \@stock_data ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " plasmid entries. Missed $missed entries" );
    }
    return;
}

sub import_props {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my @stock_props;
    my $rank             = 0;
    my $previous_type_id = 0;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $strain_props;
            $strain_props->{stock_id} = $self->find_stock( $fields[0] );
            if ( !$strain_props->{stock_id} ) {
                $self->logger->debug("Failed import of props for $fields[0]");
                next;
            }
            $strain_props->{type_id}
                = $self->find_or_create_cvterm( $fields[1],
                'dicty_stockcenter' );
            $rank = 0 if $previous_type_id ne $strain_props->{type_id};
            $strain_props->{value} = $fields[2];
            $strain_props->{rank}  = $rank;
            push @stock_props, $strain_props;
            $rank             = $rank + 1;
            $previous_type_id = $strain_props->{type_id};
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 3 - scalar @stock_props;
    if ( $self->schema->resultset('Stock::Stockprop')
        ->populate( \@stock_props ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_props
                . " plasmid property entries. Missed $missed entries" );
    }
    return;
}

sub import_publications {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $data;
            $data->{stock_id} = $self->find_stock( $fields[0] );
            if ( !$data->{stock_id} ) {
                $self->logger->debug(
                    "Failed import of publication for $fields[0]");
                next;
            }
            $data->{pub_id}
                = $self->find_pub( $fields[1] );
            if ( !$data->{pub_id} ) {
                $self->logger->debug(
                    "Couldn't find publication for $fields[1]");
                next;
            }
            push @stock_data, $data;
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 2 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::StockPub')->populate( \@stock_data )
        )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " plasmid publication entries. Missed $missed entries" );
    }
    return;
}

sub import_inventory {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    my $inventory_ontology_name = 'plasmid_inventory';

    croak "Please load plasmid_inventory ontology!"
        if !$self->utils->is_ontology_loaded($inventory_ontology_name);
    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my $transform = Modware::Import::Stock::DataTransformer->new();

    my @stock_data;
    my $rank              = 0;
    my $previous_stock_id = 0;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBP ID");
                next;
            }

            my $inventory
                = $transform->convert_row_to_plasmid_inventory_hash(@fields);
            foreach my $key ( keys %$inventory ) {
                my $data;
                $data->{stock_id} = $self->find_stock( $fields[0] );
                if ( !$data->{stock_id} ) {
                    $self->logger->debug(
                        "Failed import of inventory for $fields[0]");
                    next;
                }
                my $type = $key;
                $type =~ s/_/ /g if $type =~ /_/;
                $data->{type_id}
                    = $self->find_cvterm( $type, $inventory_ontology_name );
                if ( !$data->{type_id} ) {
                    $self->logger->debug(
                        "Couldn't find $key from $inventory_ontology_name");
                    next;
                }
                $rank = 0 if $previous_stock_id ne $data->{stock_id};
                $data->{value} = $inventory->{$key};
                $data->{rank}  = $rank;
                push @stock_data, $data;

                $previous_stock_id = $data->{stock_id};
            }

        }
        $rank = $rank + 1;
    }
    $io->close();
    my $missed = $csv->record_number() / 6 - scalar @stock_data / 6;
    if ($self->schema->resultset('Stock::Stockprop')->populate( \@stock_data )
        )
    {
        $self->logger->info( "Imported "
                . ( scalar @stock_data / 6 )
                . " plasmid inventory entries. Missed $missed entries" );
    }
    return;
}

sub import_images {
    my ( $self, $base_url ) = @_;
    $self->logger->info("Importing data from images");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    my $dbh = $self->schema->storage->dbh;
    my $stock_ids
        = $dbh->selectall_arrayref(
        qq{SELECT s.uniquename FROM stock s JOIN cvterm typ ON typ.cvterm_id = s.type_id WHERE typ.name = 'plasmid'}
        );

    my $image_type_id
        = $self->find_or_create_cvterm( 'plasmid map', 'dicty_stockcenter' );

    my @stock_data;
    for my $dbp_id ( @{$stock_ids} ) {
        ( my $filename = $dbp_id->[0] ) =~ s/^DBP[0]+//;
        my $image_url = $base_url . $filename . ".jpg";
        my $data;
        if ( head($image_url) ) {
            $data->{stock_id} = $self->find_stock($dbp_id);
            if ( !$data->{stock_id} ) {
                $self->logger->debug(
                    "Failed to import plasmid map for $dbp_id");
                next;
            }
            $data->{type_id} = $image_type_id;
            $data->{value}   = $image_url;
            push @stock_data, $data;
        }
    }
    if ($self->schema->resultset('Stock::Stockprop')->populate( \@stock_data )
        )
    {
        $self->logger->info(
            "Imported " . scalar @stock_data . " plasmid map entries." );
    }
    return;
}

sub import_plasmid_sequence {
    my ( $self, $data_dir ) = @_;
    $self->logger->info("Importing plasmid sequences");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

# my $dbh = $self->schema->storage->dbh;
# my $stock_ids
#     = $dbh->selectall_arrayref(
#     qq{SELECT s.uniquename FROM stock s JOIN cvterm typ ON typ.cvterm_id = s.type_id WHERE typ.name = 'plasmid'}
#     );

    my $seq_dir = Path::Class::Dir->new($data_dir);
    while ( my $file = $seq_dir->next ) {
        my $fasta_seq_io;

        # say $file->basename;
        if ( $file->basename =~ m/^DBP[0-9]{7}.genbank/ ) {
            my $gb_seq_io = Bio::SeqIO->new(
                -file   => $file->stringify,
                -format => 'genbank'
            );

            my $tmp_fasta_file = File::Temp->new(
                UNLINK => 0,
                EXLOCK => 0,
                SUFFIX => '.fa'
            );

            my $string   = undef;
            my $stringio = IO::String->new($string);
            $fasta_seq_io = Bio::SeqIO->new(
                -fh     => $stringio,
                -format => 'fasta'
            );
            print $string;
            while ( my $gb_seq = $gb_seq_io->next_seq() ) {
                $fasta_seq_io->write_seq($gb_seq);
            }
            while ( my $fasta = $fasta_seq_io->next_seq ) {
                say $file->basename . "\t" . $fasta->id;
            }
        }
        elsif ( $file->basename =~ m/^DBP[0-9]{7}.fasta/ ) {
            $fasta_seq_io = Bio::SeqIO->new(
                -file   => $file->stringify,
                -format => 'fasta'
            );
        }
        else {
            next;
        }
        $self->_load_fasta($fasta_seq_io) if $fasta_seq_io;
    }
    File::Temp::cleanup();
    return;
}

sub _load_fasta {
    my ( $self, $seqio ) = @_;
    my $type_id = $self->find_cvterm('plasmid');
    while ( my $seq = $seqio->next_seq ) {
        my $stock_name = $self->find_stock_name( $seq->id );
        my $name       = $seq->id;
        $name = $stock_name if $stock_name;
        say sprintf "%s\t%s\t%s\t%d\t%d", $name, $seq->id,
            md5_hex( $seq->seq ), $seq->length, $type_id;
        my $feature = {
            name        => $name,
            uniquename  => $seq->id,
            residues    => $seq->seq,
            seqlen      => $seq->length,
            md5checksum => md5_hex( $seq->seq ),
            type_id     => $type_id
        };
    }

}

1;

__END__