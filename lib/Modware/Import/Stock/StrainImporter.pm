package Modware::Import::Stock::StrainImporter;

use strict;
use feature 'say';
use Moose;
use namespace::autoclean;
use Text::CSV;
use Modware::Import::Stock::DataTransformer;
use Modware::Import::Utils;

has schema => ( is => 'rw', isa => 'DBIx::Class::Schema' );
has logger => ( is => 'rw', isa => 'Log::Log4perl::Logger' );
has utils  => ( is => 'rw', isa => 'Modware::Import::Utils' );
has cv_namespace =>
    ( is => 'rw', isa => 'Str', default => 'dicty_stockcenter' );
has stock_collection => (
    is => 'rw', isa => 'Str', default => 'Dicty stock center'
);

with 'Modware::Role::Stock::Import::DataStash';

sub prune_stock {
    my ($self) = @_;
    my $type_id
        = $self->find_cvterm( 'strain', $self->cv_namespace );
        if (!$type_id) {
            $self->logger->warn(
                "could not find strain cvterm, nothing to be pruned");
            return;
        }
    $self->schema->resultset('Stock::Stock')->delete({
            'type_id' => $type_id
        });
}

sub import_stock {
    my ( $self, $input ) = @_;
    $self->logger->debug("Importing data from $input");
    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logdie("Cannot open file: $input");
    my $count = 0;
    my $type_id
        = $self->find_or_create_cvterm( 'strain', $self->cv_namespace );
    my $stockcollection_id
        = $self->find_or_create_stockcolletion( $self->stock_collection,
        $type_id );

    my $existing_stock = [];
    my $new_stock      = [];
    my $counter = 0;
    while ( my $line = $io->getline() ) {
        chomp $line;
        $counter++;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
            $self->logger->warn(
                "Line starts with $fields[0]. Expected DBS ID");
            next;
        }
        if ( my $stock_obj = $self->find_stock_object( $fields[0] ) ) {
            push @$existing_stock, $stock_obj;
            $self->logger->debug("$fields[0] exists in database");
            next;
        }

        my $strain;
        $strain->{uniquename}  = $fields[0];
        $strain->{name}        = $fields[1];
        $strain->{organism_id} = $self->find_or_create_organism( $fields[2] );
        $strain->{description}
            = $self->utils->wiki_converter->html2wiki(
            $self->utils->trim( $fields[3] ) )
            if $fields[3];
        $strain->{type_id} = $type_id;
        $strain->{stockcollection_stocks}
            = [ { stockcollection_id => $stockcollection_id } ];
        push @$new_stock, $strain;
    }
    $io->close();
    my $new_count      = @$new_stock      ? scalar @$new_stock      : 0;
    my $existing_count = @$existing_stock ? scalar @$existing_stock : 0;
    my $missed = $counter - ( $new_count + $existing_count );
    if ( $self->schema->resultset('Stock::Stock')->populate($new_stock) ) {
        $self->logger->info( "Imported "
                . $new_count
                . " strain entries. Missed $missed entries" );
    }
    return $existing_stock;
}

sub import_props {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->debug("Importing data from $input");

    $self->logger->logcroak("Please load strain data first!")
        if !$self->utils->is_stock_loaded('strain');

    # Remove existing props
    my $cvterm_ids = $self->find_all_cvterms( $self->cv_namespace );
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $prop ( $row->stockprops ) {
                $prop->delete( { 'type_id' => { -in => $cvterm_ids } } );
            }
        }
        $self->logger->info(
            sprintf( "removed props for %d stock entries",
                scalar @$existing_stock )
        );
    }

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");
    my $stock_props;
    my $rank             = 0;
    my $previous_type_id = 0;
    my $count            = 0;
    while ( my $line = $io->getline() ) {
        chomp $line;
        $count++;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
            $self->logger->warn(
                "Line starts with $fields[0]. Expected DBS ID");
            next;
        }

        my $strain_props;
        $strain_props->{stock_id} = $self->find_stock( $fields[0] );
        if ( !$strain_props->{stock_id} ) {
            $self->logger->warn("Failed import of props for $fields[0]");
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
    my $new_count = @$stock_props ? scalar @$stock_props : 0;
    my $missed = $count - $new_count;
    if ($self->schema->resultset('Stock::Stockprop')->populate($stock_props) )
    {
        $self->logger->info( "Imported "
                . $new_count
                . " strain property entries. Missed $missed entries" );
    }
}

sub import_inventory {
    my ( $self, $input, $existing_stock ) = @_;
    my $logger = $self->logger;
    $logger->info("Importing data from $input");

    $logger->logcroak("Please load strain_inventory ontology!")
        if !$self->utils->is_ontology_loaded('strain_inventory');
    $logger->logcroak("Please load strain data first!")
        if !$self->utils->is_stock_loaded('strain');

    # Remove existing props
    my $cvterm_ids = $self->find_all_cvterms('strain_inventory');
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $prop ( $row->stockprops ) {
                $prop->delete( { 'type_id' => { -in => $cvterm_ids } } );
            }
        }
        $self->logger->info(
            sprintf( "pruned inventories for %d stock entries",
                scalar @$existing_stock )
        );
    }

    my $io = IO::File->new( $input, 'r' )
        or $logger->logcroak("Cannot open file: $input");

    my $transform = Modware::Import::Stock::DataTransformer->new();

    my $stock_data;
    my $rank              = 0;
    my $previous_stock_id = 0;
    my $counter           = 0;
    my $total             = 0;
STOCK:
    while ( my $line = $io->getline() ) {
        chomp $line;
        $counter++;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
            $logger->warn("Line starts with $fields[0]. Expected DBS ID");
            next;
        }
        my $stock_id = $self->find_stock( $fields[0] );
        if ( !$stock_id ) {
            $logger->warn("Failed import of inventory for $fields[0]");
            next STOCK;
        }

        my $inventory
            = $transform->convert_row_to_strain_inventory_hash(@fields);

        if ( $stock_id == $previous_stock_id ) {
            $rank++;
        }
        else {
            $rank = 0;
        }
    INVENTORY:
        foreach my $key ( keys %$inventory ) {
            my $data;
            $data->{stock_id} = $stock_id;
            $data->{type_id} = $self->find_cvterm( $key, 'strain_inventory' );
            if ( !$data->{type_id} ) {
                $logger->warn(
                    "Couldn't find $key from strain_inventory ontology");
                next INVENTORY;
            }
            $data->{value} = $inventory->{$key};
            $data->{rank}  = $rank;
            push @$stock_data, $data;
        }
        $previous_stock_id = $stock_id;
        $total++;
    }
    $io->close();
    if ( $self->schema->resultset('Stock::Stockprop')->populate($stock_data) )
    {
        $logger->info( "imported $total invertory records, missed "
                . ( $counter - $total )
                . " entries" );
    }
}

sub import_publications {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->info("Importing data from $input");

    $self->logger->logcroak("Please load strain data first!")
        if !$self->utils->is_stock_loaded('strain');

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");

    # Remove existing stock and pub links
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $pub_rel ( $row->stock_pubs ) {
                $pub_rel->delete;
            }
        }
        $self->logger->info(
            sprintf( "pruned publication links for %d stock entries",
                scalar @$existing_stock )
        );
    }
    my $stock_data;
    my $counter = 0;
    while ( my $line = $io->getline() ) {
        chomp $line;
        $counter++;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
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
            $self->logger->warn("Couldn't find publication for $fields[1]");
            next;
        }
        push @$stock_data, $data;
    }
    $io->close();
    my $missed = $counter - @$stock_data;
    if ( $self->schema->resultset('Stock::StockPub')->populate($stock_data) )
    {
        $self->logger->info( "Imported "
                . @$stock_data
                . " strain publication entries. Missed $missed entries" );
    }
}

sub import_characteristics {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->info("Importing data from $input");

    $self->logger->logcroak("Please load strain_characteristics ontology!")
        if !$self->utils->is_ontology_loaded('strain_characteristics');
    $self->logger->logcroak("Please load strain data first!")
        if !$self->utils->is_stock_loaded('strain');

    my $strain_char_pub_title = 'Dicty Strain Characteristics';
    my $char_pub_id = $self->find_pub_by_title($strain_char_pub_title)
        or $self->logger->logcroak(
        "Pub reference for strain_characteristics ontology not found!");

    # Remove existing props
    my $cvterm_ids = $self->find_all_cvterms('strain_characteristics');
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $cvt ( $row->stock_cvterms ) {
                $cvt->delete( { 'cvterm_id' => { -in => $cvterm_ids } } );
            }
        }
        $self->logger->info(
            sprintf( "removed characteristics for %d stock entries",
                scalar @$existing_stock )
        );
    }

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");
    my $stock_data;
    my $counter = 0;
    my $total   = 0;
    while ( my $line = $io->getline() ) {
        chomp $line;
        $counter++;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
            $self->logger->warn(
                "Line starts with $fields[0]. Expected DBS ID");
            next;
        }

        my $data;
        $data->{stock_id} = $self->find_stock( $fields[0] );
        if ( !$data->{stock_id} ) {
            $self->logger->warn(
                "Failed import of characteristics for $fields[0]");
            next;
        }
        $data->{cvterm_id}
            = $self->find_cvterm( $fields[1], 'strain_characteristics' );
        if ( !$data->{stock_id} ) {
            $self->logger->warn(
                "Couldn't find $fields[1] in strain_characteristics ontology"
            );
            next;
        }
        $data->{pub_id} = $char_pub_id;
        push @$stock_data, $data;
        $total++;
    }
    $io->close();
    if ( $self->schema->resultset('Stock::StockCvterm')->populate($stock_data)
        )
    {
        $self->logger->info(
            "Imported "
                . scalar @$stock_data
                . " strain characteristics entries. Missed ",
            ( $counter - $total ),
            " entries"
        );
    }
    return;
}

sub import_genotype {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->debug("Importing data from $input");

    $self->logger->logcroak("Please load strain data first!")
        if !$self->utils->is_stock_loaded('strain');

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");

    #cleanup all genotypes
    $self->schema->resultset('Genetic::Genotype')->delete;
    my $genotype_type_id
        = $self->find_or_create_cvterm( 'genotype', 'dicty_stockcenter' );
    my $stock_data;
    my $counter = 0;
    my $total   = 0;
    while ( my $line = $io->getline() ) {
        $counter++;
        chomp $line;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
            $self->logger->warn(
                "Line starts with $fields[0]. Expected DBS ID");
            next;
        }

        my $data;
        my $stock_id = $self->find_stock( $fields[0] );
        if ( !$stock_id ) {
            $self->logger->warn("Failed import of genotype for $fields[0]");
            next;
        }
        $data->{name} = $fields[2];

        # $data->{uniquename}      = $self->generate_uniquename('DSC_G');
        $data->{uniquename} = $self->utils->nextval( 'genotype', 'DSC_G' );
        $data->{type_id} = $genotype_type_id;
        $data->{stock_genotypes} = [ { stock_id => $stock_id } ];
        push @$stock_data, $data;
        $total++;
    }
    $io->close();
    my $missed = $counter - @$stock_data;
    if ($self->schema->resultset('Genetic::Genotype')->populate($stock_data) )
    {
        $self->logger->info(
            "Imported " . scalar @$stock_data . " genotype entries. Missed ",
            $missed,
            " entries"
        );
    }
    return;
}

sub import_phenotype {
    my ( $self, $input, $dsc_phenotypes, $existing_stock ) = @_;
    my $logger = $self->logger;

    $logger->logcroak("Please load strain data first!")
        if !$self->utils->is_stock_loaded('strain');
    $logger->logcroak("Please load Dicty Phenotypes ontology!")
        if !$self->utils->is_ontology_loaded('Dicty Phenotypes');
    $logger->logcroak("Please load Dicty Environment ontology!")
        if !$self->utils->is_ontology_loaded('Dicty Environment');
    $logger->logcroak("Please load genotype data first!")
        if !$self->utils->is_genotype_loaded();

    my $type_id
        = $self->find_or_create_cvterm( "observation", "dicty_stockcenter" );

    my $default_pub_id
        = $self->find_pub_by_title("Dicty stock center phenotyping 2003-2008")
        or $logger->logcroak(
        "Dicty Phenotypes ontology reference not available");

    #cleanup existing phenotype
    $self->schema->resultset('Phenotype::Phenotype')->delete;
    my @files = ( $input, $dsc_phenotypes );
    for my $f (@files) {
        next if !$f;
        $self->logger->info("Importing data from $f");
        my $io = IO::File->new( $f, 'r' )
            or $logger->logcroak("Cannot open file: $f");

        my $stock_data;
        my $counter = 0;
        while ( my $line = $io->getline() ) {
            chomp $line;
            $counter++;
            my @fields = split "\t", $line;
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->warn(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $data;
            $data->{phenotype_id}
                = $self->find_or_create_phenotype( $fields[1], $fields[3],
                $fields[5] );
            if ( !$data->{phenotype_id} ) {
                $self->logger->warn("Couldn't find phenotype for $fields[1]");
                next;
            }

            # The genotype needs to be present
            $data->{genotype_id} = $self->find_genotype( $fields[0] );
            if ( !$data->{genotype_id} ) {
                $self->logger->warn("Couldn't find genotype for $fields[0]");
                next;
            }
            $data->{environment_id}
                = $self->find_or_create_environment( $fields[2] );
            if ( !$data->{environment_id} ) {
                $self->logger->warn(
                    "Couldn't find environment for $fields[2]");
                next;
            }
            $data->{type_id} = $type_id;
            $data->{pub_id}  = $self->find_pub( $fields[4] );
            if ( !$data->{pub_id} ) {
                my $msg
                    = "Couldn't find publication for $fields[4]. Using default for phenotype";
                $msg = "No PMID provided. Using default for phenotype"
                    if !$fields[4];
                $self->logger->warn($msg);
                $data->{pub_id} = $default_pub_id;
            }
            push @$stock_data, $data;
        }
        $io->close();
        my $missed = $counter - @$stock_data;
        my $ret    = $self->schema->resultset('Genetic::Phenstatement')
            ->populate($stock_data);
        if ($ret) {
            $self->logger->info(
                sprintf(
                    "Imported %d, missed %d entries from %s\n",
                    @$stock_data, $missed, $f
                )
            );
        }
    }
}

sub import_parent {
    my ( $self, $input, $existing_stock ) = @_;
    $self->logger->debug("Importing data from $input");

    $self->logger->logcroak("Please load strain data first!")
        if !$self->utils->is_stock_loaded('strain');

    my $io = IO::File->new( $input, 'r' )
        or $self->logger->logcroak("Cannot open file: $input");

    my $stock_rel_type_id
        = $self->find_or_create_cvterm( 'is_parent_of', 'stock_relation' );

    # cleanup previous data
    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $obj ( $row->stock_relationship_objects ) {
                $obj->delete;
            }
            for my $obj ( $row->stock_relationship_subjects ) {
                $obj->delete;
            }
        }
        $self->logger->info(
            sprintf( "removed parents/children for %d stock entries",
                @$existing_stock )
        );
    }
    my $stock_data;
    my $counter = 0;
    while ( my $line = $io->getline() ) {
        $counter++;
        chomp $line;
        my @fields = split "\t", $line;
        if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
            $self->logger->warn(
                "Line starts with $fields[0]. Expected DBS ID");
            next;
        }

        my $data;
        $data->{object_id} = $self->find_stock( $fields[0] );
        if ( !$data->{object_id} ) {
            $self->logger->warn(
                "Failed import of parental strain for $fields[0]");
            next;
        }
        $data->{subject_id} = $self->find_stock( $fields[1] );
        if ( !$data->{subject_id} ) {
            $self->logger->warn(
                "Couldn't find $fields[1] parental strain entry");
            $self->logger->warn("$fields[0] no parent exists in database");
            next;
        }
        $data->{type_id} = $stock_rel_type_id;
        push @$stock_data, $data;
    }
    $io->close();
    my $missed = $counter - @$stock_data;
    if ( $self->schema->resultset('Stock::StockRelationship')
        ->populate( $stock_data ) )
    {
        $self->logger->info( "Imported "
                . @$stock_data
                . " parental strain entries. Missed $missed entries" );
    }
}

sub import_plasmid {
    my ( $self, $input, $strain_plasmid, $existing_stock ) = @_;

    $self->logger->logcroak("Please load strain data first!")
        if !$self->utils->is_stock_loaded('strain');
    $self->logger->logcroak(
        "Please load plasmid data before loading strain-plasmid!")
        if !$self->utils->is_stock_loaded('plasmid');

    my $stock_rel_type_id
        = $self->find_or_create_cvterm( 'part_of', 'stock_relation' );

    my $plasmid_type_id
        = $self->find_or_create_cvterm( 'plasmid', $self->cv_namespace );

    if ( @$existing_stock > 0 ) {
        for my $row (@$existing_stock) {
            for my $obj ( $row->stock_relationship_subjects ) {
                $obj->delete({type_id => $stock_rel_type_id});
            }
        }
        $self->logger->info(
            sprintf( "removed plasmid relationships for %d stock entries",
                @$existing_stock )
        );
    }

    my @files = ( $input, $strain_plasmid );
    for my $f (@files) {
        next if !$f;
        $self->logger->info("Importing data from $f");

        my $io = IO::File->new( $f, 'r' )
            or $self->logger->logcroak("Cannot open file: $f");
        my $stock_data;
        while ( my $line = $io->getline() ) {
            chomp $line;
            my @fields = split "\t", $line;
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->warn(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $data;
            $data->{object_id} = $self->find_stock( $fields[0] );
            if ( !$data->{object_id} ) {
                $self->logger->warn(
                    "Failed import of strain-plasmid for $fields[0]");
                next;
            }
            my $stock_plasmid_id;
            if ( $fields[1] =~ m/^[0-9]{1,3}$/ ) {
                $fields[1] = sprintf( "DBP%07d", $fields[1] );
            }
            if ( $fields[1] =~ m/DBP[0-9]{7}/ ) {
                $stock_plasmid_id = $self->find_stock( $fields[1] );
                if ( !$stock_plasmid_id ) {
                    $self->logger->warn(
                        $fields[1] . " plasmid entry not found" );
                    next;
                }
            }
            else {
                $stock_plasmid_id = $self->find_stock_by_name( $fields[1] );
                if ( !$stock_plasmid_id ) {
                    $self->logger->debug(
                        "Couldn't find $fields[1] strain-plasmid. Creating one"
                    );

                    my 
                    $stockcollection_id
                        = $self->find_or_create_stockcollection('External laboratory', $plasmid_type_id);
                    if ( !$stockcollection_id ) {
                        $self->logger->warn("Could not create stock collection External laboratory for plasmid $fields[1]");
                        next;
                    }

                    my $new_plasmid;
                    $new_plasmid->{name} = $fields[1];
                    $new_plasmid->{uniquename}
                        = $self->utils->nextval( 'stock', 'DBP' );
                    $new_plasmid->{type_id} = $plasmid_type_id;
                    $new_plasmid->{description}
                        = 'Autocreated strain-plasmid';
                    $new_plasmid->{stockcollection_stocks}
                        = [ { stockcollection_id => $stockcollection_id } ];

                    my $plasmid_rs
                        = $self->schema->resultset('Stock::Stock')
                        ->create($new_plasmid);
                    $stock_plasmid_id = $plasmid_rs->stock_id;
                    $self->logger->info("created plasmid $fields[1]");
                }
            }
            $data->{subject_id} = $stock_plasmid_id;
            $data->{type_id}    = $stock_rel_type_id;
            push @$stock_data, $data;
        }
        $io->close();
        my $retval = $self->schema->resultset('Stock::StockRelationship')->populate($stock_data);
        if ($retval) {
            $self->logger->info(sprintf("created %d strain plasmid relationships", @$stock_data));
        }
    }
}

1;

__END__
