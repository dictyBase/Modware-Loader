
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
use Modware::Import::Stock::DataTransformer;

has schema       => ( is => 'rw', isa => 'DBIx::Class::Schema' );
has logger       => ( is => 'rw', isa => 'Log::Log4perl::Logger' );
has utils        => ( is => 'rw', isa => 'Modware::Import::Utils' );
has cv_namespace => ( is => 'rw', isa => 'Str' );
has stock_collection => (
    is      => 'rw',
    isa     => 'Str',
    default => 'Dicty stock center'
);

with 'Modware::Role::Stock::Import::DataStash';

sub prune_plasmid {
    my ($self) = @_;
    my $type_id = $self->find_cvterm( 'plasmid', $self->cv_namespace );
    if ( !$type_id ) {
        $self->logger->warn(
            "could not find plasmid cvterm, nothing to be pruned");
        return;
    }
    $self->schema->resultset('Stock::Stock')
        ->delete( { 'type_id' => $type_id } );
}

sub import_plasmid {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");

    my $type_id
        = $self->find_or_create_cvterm( 'plasmid', $self->cv_namespace );
    my $sc_id = $self->find_or_create_stockcolletion( $self->stock_collection,
        $type_id );

    my $existing_stock = [];
    my $new_stock      = [];
    my $counter        = 0;
    while ( my $line = $io->getline() ) {
        chomp $line;
        $counter++;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
            $self->logger->warn(
                "Line starts with $fields[0]. Expected DBP ID");
            next;
        }
        if ( my $stock_obj = $self->find_stock_object( $fields[0] ) ) {
            push @$existing_stock, $stock_obj;
            $self->logger->debug("$fields[0] exists in database");
            next;
        }
        my $data;
        $data->{uniquename}  = $fields[0];
        $data->{name}        = $fields[1];
        $data->{description} = $self->utils->trim( $fields[2] )
            if $fields[2];
        $data->{type_id} = $type_id;
        $data->{stockcollection_stocks}
            = [ { stockcollection_id => $sc_id } ];
        push @$new_stock, $data;
    }
    $io->close();
    my $new_count      = @$new_stock      ? @$new_stock      : 0;
    my $existing_count = @$existing_stock ? @$existing_stock : 0;
    my $missed = $counter - ( $new_count + $existing_count );
    if ( $self->schema->resultset('Stock::Stock')->populate($new_stock) ) {
        $self->logger->info(
            sprintf(
                "Imported %d plasmid entries, missed %d entries",
                @$new_stock, $missed
            )
        );
    }
    return $existing_stock;
}

sub import_props {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    # Remove existing props
    my $cvterm_ids = $self->find_all_cvterms( $self->cv_namespace );
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $prop ( $row->stockprops ) {
                $prop->delete( { 'type_id' => { -in => $cvterm_ids } } );
            }
        }
        $self->logger->info(
            sprintf( "removed props for %d stock entries", @$existing_stock )
        );
    }

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");
    my $stock_props;
    my $rank             = 0;
    my $previous_type_id = 0;
    my $counter          = 0;
    while ( my $line = $io->getline() ) {
        $counter++;
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
            = $self->find_or_create_cvterm( $fields[1], $self->cv_namespace );
        $rank = 0 if $previous_type_id ne $strain_props->{type_id};
        $strain_props->{value} = $fields[2];
        $strain_props->{rank}  = $rank;
        push @$stock_props, $strain_props;
        $rank             = $rank + 1;
        $previous_type_id = $strain_props->{type_id};
    }
    $io->close();
    my $missed = $counter - @$stock_props;
    if ( $self->schema->resultset('Stock::Stockprop')->populate(@$stock_props)
        )
    {
        $self->logger->info( "Imported "
                . @$stock_props
                . " plasmid property entries. Missed $missed entries" );
    }
}

sub import_publications {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    # Remove existing stock and pub links
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $pub_rel ( $row->stock_pubs ) {
                $pub_rel->delete;
            }
        }
        $self->logger->info(
            sprintf( "pruned publication links for %d stock entries",
                @$existing_stock )
        );
    }
    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");
    my $stock_data;
    my $counter = 0;
    while ( my $line = $io->getline() ) {
        $counter++;
        chomp $line;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
            $self->logger->warn(
                "Line starts with $fields[0]. Expected DBS ID");
            next;
        }

        my $data;
        $data->{stock_id} = $self->find_stock( $fields[0] );
        if ( !$data->{stock_id} ) {
            $self->logger->warn(
                "Failed import of publication for $fields[0]");
            next;
        }
        $data->{pub_id} = $self->find_pub( $fields[1] );
        if ( !$data->{pub_id} ) {
            $self->logger->warn("missing pubmed id $fields[1]");
            next;
        }
        push @$stock_data, $data;
        $self->logger->debug("processed data for $fields[0] and $fields[1]");
    }
    $io->close();
    my $missed = $counter - @$stock_data;
    if ( $self->schema->resultset('Stock::StockPub')->populate($stock_data) )
    {
        $self->logger->info( "Imported "
                . @$stock_data
                . " plasmid publication entries. Missed $missed entries" );
    }
    return;
}

sub import_inventory {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->info("Importing data from $input");

    my $inventory_ontology_name = 'plasmid_inventory';
    $self->logger->logcroak("Please load plasmid_inventory ontology!")
        if !$self->utils->is_ontology_loaded($inventory_ontology_name);
    $self->logger->logcroak("Please load plasmid data first!")
        if !$self->utils->is_stock_loaded('plasmid');

    # Remove existing inventory
    my $cvterm_ids = $self->find_all_cvterms('plasmid_inventory');
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $prop ( $row->stockprops ) {
                $prop->delete( { 'type_id' => { -in => $cvterm_ids } } );
            }
        }
        $self->logger->info(
            sprintf( "pruned inventories for %d stock entries",
                @$existing_stock )
        );
    }
    my $transform = Modware::Import::Stock::DataTransformer->new();
    my $stock_data;
    my $rank              = 0;
    my $previous_stock_id = 0;

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");
    my $counter = 0;
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
            $counter++;
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
            push @$stock_data, $data;

            $previous_stock_id = $data->{stock_id};

        }
        $rank = $rank + 1;
    }
    $io->close();
    my $missed = $counter - @$stock_data;
    if ( $self->schema->resultset('Stock::Stockprop')->populate($stock_data) )
    {
        $self->logger->info(
            sprintf(
                "Imported %d plasmid inventory entries, missed %d entries",
                @$stock_data, $missed
            )
        );
    }
}

sub import_images {
    my ( $self, $base_url, $existing_stock ) = @_;
    $self->logger->info("Importing data from images");
    $self->logger->logcroak("Please load plasmid data first!")
        if !$self->utils->is_stock_loaded('plasmid');

    my $image_type_id
        = $self->find_or_create_cvterm( 'plasmid map', 'dicty_stockcenter' );
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $prop ( $row->stockprops ) {
                $prop->delete( { 'type_id' => $image_type_id } );
            }
            $self->logger->info(
                sprintf( "pruned image links for %d stock entries",
                    @$existing_stock )
            );
        }
    }
    my $type_id = $self->find_cvterm( 'plasmid', $self->cv_namespace );
    if ( !$type_id ) {
        $self->logger->logcroak("could not find plasmid cvterm");
    }
    my $stock_rs = $self->schema->resultset('Stock::Stock')
        ->search( { type_id => $type_id } );
    my $stock_data;
    my $counter = 0;
    while ( my $row = $stock_rs->next ) {
        $counter++;
        ( my $filename = $row->uniquename ) =~ s/^DBP[0]+//;
        my $image_url = $base_url . $filename . ".jpg";
        my $data;
        if ( head($image_url) ) {
            $self->logger->warn("image $image_url found");
            $data->{stock_id} = $self->find_stock( $row->uniquename );
            if ( !$data->{stock_id} ) {
                $self->logger->warn( "Failed to import plasmid map for ",
                    $row->uniquename );
                next;
            }
            $data->{type_id} = $image_type_id;
            $data->{value}   = $image_url;
            push @$stock_data, $data;
        }
        else {
            $self->logger->warn(
                "issue in retrieving image info for $image_url");
        }
    }
    if ( $self->schema->resultset('Stock::Stockprop')->populate($stock_data) )
    {
        $self->logger->info(
            "Imported " . @$stock_data . " plasmid map entries." );
    }
    return;
}

sub import_plasmid_sequence {
    my ( $self, $data_dir, $existing_stock ) = @_;
    $self->logger->info("Importing plasmid sequences");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    my $type_id = $self->find_cvterm( 'plasmid_vector', 'sequence' );
    if ( !$type_id ) {
        $self->logger->logcroak("plasmid_vector SO term not found");
    }
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $prop ( $row->stockprops ) {
                $prop->delete( { 'type_id' => $type_id } );
            }
        }
        $self->logger->info(
            sprintf( "removed props for %d stock entries", @$existing_stock )
        );
    }
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
}

sub _load_fasta {
    my ( $self, $seqio, $dbp_id ) = @_;
    my $type_id = $self->find_cvterm( 'plasmid_vector', 'sequence' );
    if ( !$type_id ) {
        $self->logger->logcroak("plasmid_vector SO term not found");
    }
    my $organism_id = $self->find_organism('Dictyostelium discoideum');
    if ( !$organism_id ) {
        $self->logger->logcroak(
            "organism Dictyostelium discoideum does not exist");
    }
    while ( my $seq = $seqio->next_seq ) {
        my $dbxref_id;
        if ( $seq->id ne $dbp_id ) {
            $self->db('GenBank');
            $dbxref_id = $self->find_or_create_dbxref( $seq->id );
        }
        my $feature = {
            uniquename  => $self->utils->nextval( 'feature', 'DBP' ),
            residues    => $seq->seq,
            seqlen      => $seq->length,
            md5checksum => md5_hex( $seq->seq ),
            type_id     => $type_id,
            dbxref_id   => $dbxref_id,
            organism_id => $organism_id
        };
        my $frow
            = $self->schema->resultset('Sequence::Feature')->create($feature);
        my $stock_id = $self->find_stock($dbp_id);
        if ( $frow->in_storage and $stock_id ) {
            $self->schema->resultset('Stock::Stockprop')->create(
                {   stock_id => $stock_id,
                    type_id  => $type_id,
                    value    => $frow->feature_id
                }
            );
        }
        else {
            $self->logger->warn(
                'Sequence present but no stock entry for ' . $dbp_id );
        }
    }
}

sub import_genes {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load plasmid data first!"
        if !$self->utils->is_stock_loaded('plasmid');

    my $io = IO::File->new( $input, 'r' )
        or croak "Cannot open file: $input";

    my $rel_type_id = $self->find_cvterm( 'part_of', 'ro' );
    if ( !$rel_type_id ) {
        $self->logger->logcroak("part_of relationship term not found");
    }
    my $seq_type_id = $self->find_cvterm( 'plasmid_vector', 'sequence' );
    if ( !$seq_type_id ) {
        $self->logger->logcroak("plasmid_vector SO term not found");
    }
    my $organism_id = $self->find_organism('Dictyostelium discoideum');
    if ( !$organism_id ) {
        $self->logger->logcroak(
            "organism Dictyostelium discoideum does not exist");
    }
    my $gene_type_id
        = $self->find_or_create_cvterm( 'plasmid gene', 'dicty_stockcenter' );

    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            my @props = $row->stockprops( { type_id => $gene_type_id } );
            $self->schema->resultset('Sequence::Feature')
                ->delete( { uniquename => $props[0]->value } );
            $props[0]->delete;
        }
        $self->logger->info(
            sprintf( "removed gene links for %d stock entries",
                @$existing_stock )
        );
    }
    my $stock_props;
    my $counter = 0;
    while ( my $line = $io->getline() ) {
        $counter++;
        chomp $line;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBP[0-9]{7}/ ) {
            $self->logger->debug(
                "Line starts with $fields[0]. Expected DBS ID");
            next;
        }
        my $frow = $self->schema->resultset('Sequence::Feature')
            ->find( { uniquename => $fields[1] } );
        if ( !$frow ) {
            $self->logger->warn("could not find gene id $fields[1]");
            next;
        }
        my $prow = $self->schema->resultset('Sequence::Feature')->create(
            {   uniquename  => $self->utils->nextval( 'feature', 'DBP' ),
                type_id     => $seq_type_id,
                organism_id => $organism_id,
                feature_relationship_subjects => [
                    {   type_id    => $rel_type_id,
                        subject_id => $frow->feature_id
                    }
                ]
            }
        );

        my $plasmid_genes;
        $plasmid_genes->{stock_id} = $self->find_stock( $fields[0] );
        if ( !$plasmid_genes->{stock_id} ) {
            $self->logger->warn("Failed import of props for $fields[0]");
            next;
        }

        # create the plasmid feature
        $plasmid_genes->{type_id} = $seq_type_id;
        $plasmid_genes->{value}   = $prow->uniquename;
        push @$stock_props, $plasmid_genes;
    }
    $io->close();
    my $missed = $counter - @$stock_props;
    if ($self->schema->resultset('Stock::Stockprop')->populate($stock_props) )
    {
        $self->logger->info( "Imported "
                . @$stock_props
                . " plasmid-gene entries. Missed $missed entries" );
    }
}

1;

__END__
