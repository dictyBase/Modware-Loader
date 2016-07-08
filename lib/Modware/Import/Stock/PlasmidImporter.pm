
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
has cv_namespace =>
    ( is => 'rw', isa => 'Str', default => 'dicty_stockcenter' );
has stock_collection => (
    is => 'rw', isa => 'Str', default => 'Dicty stock center'
);

with 'Modware::Role::Stock::Import::DataStash';

sub prune_plasmid {
    my ($self) = @_;
    my $type_id
        = $self->find_cvterm( 'plasmid', $self->cv_namespace );
        if (!$type_id) {
            $self->logger->warn(
                "could not find plasmid cvterm, nothing to be pruned");
            return;
        }
    $self->schema->resultset('Stock::Stock')->delete({
            'type_id' => $type_id
        });
}

sub import_stock {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");

    my $type_id
        = $self->find_or_create_cvterm( 'plasmid', 'dicty_stockcenter' );
    my $stockcollection_id = 0;
    $stockcollection_id = $self->find_stockcollection('Dicty Stockcenter');
    if ( !$stockcollection_id ) {
        $stockcollection_id
            = $self->create_stockcollection( 'Dicty Stockcenter', $type_id );
    }

    my @stock_data;
    my $count = 0;
    while ( my $line = $io->getline() ) {
        chomp $line;
        $count++;
        my @fields = split "\t", $line;
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
    $io->close();
    my $missed = $count - scalar @stock_data;
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

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");
    my @stock_props;
    my $rank             = 0;
    my $previous_type_id = 0;
    my $count            = 0;
    while ( my $line = $io->getline() ) {
        $count++;
        chomp $line;
        my @fields = split "\t", $line;
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
            = $self->find_or_create_cvterm( $fields[1], 'dicty_stockcenter' );
        $rank = 0 if $previous_type_id ne $strain_props->{type_id};
        $strain_props->{value} = $fields[2];
        $strain_props->{rank}  = $rank;
        push @stock_props, $strain_props;
        $rank             = $rank + 1;
        $previous_type_id = $strain_props->{type_id};
    }
    $io->close();
    my $missed = $count - scalar @stock_props;
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

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");
    my @stock_data;
    my $count = 0;
    while ( my $line = $io->getline() ) {
        $count++;
        chomp $line;
        my @fields = split "\t", $line;
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
        $data->{pub_id} = $self->find_pub( $fields[1] );
        if ( !$data->{pub_id} ) {
            $self->logger->warn("missing pubmed id $fields[1]");
            next;
        }
        push @stock_data, $data;
        $self->logger->debug("processed data for $fields[0] and $fields[1]");
    }
    $io->close();
    my $missed = $count - scalar @stock_data;
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
    $self->logger->logcroak("Please load plasmid_inventory ontology!")
        if !$self->utils->is_ontology_loaded($inventory_ontology_name);
    $self->logger->logcroak("Please load plasmid data first!")
        if !$self->utils->is_stock_loaded('plasmid');

    my $transform = Modware::Import::Stock::DataTransformer->new();
    my @stock_data;
    my $rank              = 0;
    my $previous_stock_id = 0;

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");
    my $count = 0;
    while ( my $line = $io->getline() ) {
        chomp $line;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
            $self->logger->debug(
                "Line starts with $fields[0]. Expected DBP ID");
            next;
        }

        my $inventory
            = $transform->convert_row_to_plasmid_inventory_hash(@fields);
        foreach my $key ( keys %$inventory ) {
            my $data;
            $count++;
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
        $rank = $rank + 1;
    }
    $io->close();
    my $missed = ( $count - scalar @stock_data ) / 6;
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

    $self->logger->logcroak("Please load plasmid data first!")
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
            $self->logger->debug("image $image_url found");
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
        else {
            $self->logger->warn(
                "issue in retrieving image info for $image_url");
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

    my $seq_dir = Path::Class::Dir->new($data_dir);
    while ( my $file = $seq_dir->next ) {
        next if $file->is_dir;
        my $fasta_seq_io;
        ( my $dbp_id = $file->basename ) =~ s/.[a-z]{5,7}$//;
        if ( $file->basename =~ m/^DBP[0-9]{7}.genbank/ ) {
            my $gb_seq_io = Bio::SeqIO->new(
                -file   => $file->stringify,
                -format => 'genbank'
            );
            my $tmp_fasta_file = File::Temp->new();
            my $fasta_seq_out  = Bio::SeqIO->new(
                -file   => ">$tmp_fasta_file",
                -format => 'fasta'
            );
            while ( my $gb_seq = $gb_seq_io->next_seq() ) {
                $fasta_seq_out->write_seq($gb_seq);
            }
            $fasta_seq_io = Bio::SeqIO->new(
                -file   => $tmp_fasta_file,
                -format => 'fasta'
            );
        }
        elsif ( $file->basename =~ m/^DBP[0-9]{7}.fasta/ ) {
            $fasta_seq_io = Bio::SeqIO->new(
                -file   => $file->stringify,
                -format => 'fasta'
            );
        }
        else {
            $self->logger->warn(
                $file->basename . " does not have a DBP-ID" );
            next;
        }
        $self->_load_fasta( $fasta_seq_io, $dbp_id ) if $fasta_seq_io;
    }
    File::Temp::cleanup();
    return;
}

sub _load_fasta {
    my ( $self, $seqio, $dbp_id ) = @_;
    my $type_id = $self->find_cvterm('plasmid');
    my $organism_id
        = $self->find_or_create_organism('Dictyostelium discoideum');
    while ( my $seq = $seqio->next_seq ) {
        my $stock_name = $self->find_stock_name($dbp_id);
        my $name       = $dbp_id;
        $name = $stock_name if $stock_name;
        my $dbxref_accession = $seq->id;
        $dbxref_accession = $dbp_id if $dbxref_accession =~ m/unknown/;

        my $dbxref_id;
        if ( $dbxref_accession eq $dbp_id ) {
            $self->db('dictyBase');
            $dbxref_id = $self->find_or_create_dbxref($dbxref_accession);
        }
        else {
            $self->db('GenBank');
            $dbxref_id = $self->find_or_create_dbxref($dbxref_accession);
        }
        my @data;
        my $feature = {
            name        => $name,
            uniquename  => $dbp_id,
            residues    => $seq->seq,
            seqlen      => $seq->length,
            md5checksum => md5_hex( $seq->seq ),
            type_id     => $type_id,
            dbxref_id   => $dbxref_id,
            organism_id => $organism_id
        };
        push @data, $feature;
        my $feat_rs = $self->schema->resultset('Sequence::Feature')
            ->populate( \@data );
        my $stock_id = $self->find_stock($dbp_id);
        if ( $feat_rs and $stock_id ) {
            my $feature_id = @{$feat_rs}[0]->feature_id;
            my $sp_type_id
                = $self->find_cvterm( 'plasmid_vector', 'sequence' );
            $self->schema->resultset('Stock::Stockprop')->create(
                {   stock_id => $stock_id,
                    type_id  => $sp_type_id,
                    value    => $feature_id
                }
            );
        }
        else {
            $self->logger->warn(
                'Sequence present but no stock entry for ' . $dbp_id );
        }
    }
    return;
}

sub import_genes {

    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my $type_id = $self->find_or_create_cvterm( 'has_part', 'sequence' );
    my @stock_props;
    my $rank              = 0;
    my $previous_stock_id = 0;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $plasmid_genes;
            $plasmid_genes->{stock_id} = $self->find_stock( $fields[0] );
            if ( !$plasmid_genes->{stock_id} ) {
                $self->logger->debug("Failed import of props for $fields[0]");
                next;
            }
            $plasmid_genes->{type_id} = $type_id;
            $rank = 0 if $previous_stock_id ne $plasmid_genes->{stock_id};
            $plasmid_genes->{value} = $fields[1];
            $plasmid_genes->{rank}  = $rank;
            push @stock_props, $plasmid_genes;
            $rank              = $rank + 1;
            $previous_stock_id = $plasmid_genes->{stock_id};
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 2 - scalar @stock_props;
    if ( $self->schema->resultset('Stock::Stockprop')
        ->populate( \@stock_props ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_props
                . " plasmid-gene entries. Missed $missed entries" );
    }
    return;
}

1;

__END__
