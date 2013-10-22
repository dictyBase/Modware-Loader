
package Modware::Import::Stock::StrainImporter;

use strict;

use Carp;
use Moose;
use namespace::autoclean;
use Text::CSV;

use Modware::Import::Stock::DataTransformer;
use Modware::Import::Utils;

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
        = $self->find_or_create_cvterm( 'strain', 'dicty_stockcenter' );
    my $stockcollection_id = 0;
    $stockcollection_id = $self->find_stockcollection('Dicty Stockcenter');
    if ( !$stockcollection_id ) {
        $stockcollection_id
            = $self->create_stockcollection( 'Dicty Stockcenter', $type_id );
    }

    my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $strain;
            $strain->{uniquename} = $fields[0];
            $strain->{name}       = $fields[1];
            $strain->{organism_id}
                = $self->find_or_create_organism( $fields[2] )
                if $fields[2];
            $strain->{description} = $self->utils->trim( $fields[3] )
                if $fields[3];
            $strain->{type_id} = $type_id;
            $strain->{stockcollection_stocks}
                = [ { stockcollection_id => $stockcollection_id } ];
            push @stock_data, $strain;
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 4 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::Stock')->populate( \@stock_data ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " strain entries. Missed $missed entries" );
    }
    return;
}

sub import_props {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load strain data first!"
        if !$self->utils->is_stock_loaded('strain');

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
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
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
                . " strain property entries. Missed $missed entries" );
    }
    return;
}

sub import_inventory {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load strain_inventory ontology!"
        if !$self->utils->is_ontology_loaded('strain_inventory');
    croak "Please load strain data first!"
        if !$self->utils->is_stock_loaded('strain');

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
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $inventory
                = $transform->convert_row_to_strain_inventory_hash(@fields);
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
                    = $self->find_cvterm( $type, 'strain_inventory' );
                if ( !$data->{type_id} ) {
                    $self->logger->debug(
                        "Couldn't find $key from strain_inventory");
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
    my $missed = $csv->record_number() / 9 - scalar @stock_data / 9;
    if ($self->schema->resultset('Stock::Stockprop')->populate( \@stock_data )
        )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data / 9
                . " strain inventory entries. Missed $missed entries" );
    }
    return;
}

sub import_publications {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load strain data first!"
        if !$self->utils->is_stock_loaded('strain');

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
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
                . " strain publication entries. Missed $missed entries" );
    }
    return;
}

sub import_characteristics {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load strain_characteristics ontology!"
        if !$self->utils->is_ontology_loaded('strain_characteristics');
    croak "Please load strain data first!"
        if !$self->utils->is_stock_loaded('strain');

    my $strain_char_pub_title = 'Dicty Strain Characteristics';
    my $char_pub_id = $self->find_pub_by_title($strain_char_pub_title)
        or croak
        "Pub reference for strain_characteristics ontology not found!";

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $data;
            $data->{stock_id} = $self->find_stock( $fields[0] );
            if ( !$data->{stock_id} ) {
                $self->logger->debug(
                    "Failed import of characteristics for $fields[0]");
                next;
            }
            $data->{cvterm_id}
                = $self->find_cvterm( $fields[1], 'strain_characteristics' );
            if ( !$data->{stock_id} ) {
                $self->logger->debug(
                    "Couldn't find $fields[1] in strain_characteristics ontology"
                );
                next;
            }
            $data->{pub_id} = $char_pub_id;
            push @stock_data, $data;
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 2 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::StockCvterm')
        ->populate( \@stock_data ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " strain characteristics entries. Missed $missed entries" );
    }
    return;
}

sub import_genotype {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load strain data first!"
        if !$self->utils->is_stock_loaded('strain');

    my $io = IO::File->new( $input, 'r' )
        or confess "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or confess "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my $genotype_type_id
        = $self->find_cvterm( 'genotype', 'dicty_stockcenter' );

    my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $data;
            my $stock_id = $self->find_stock( $fields[0] );
            if ( !$stock_id ) {
                $self->logger->debug(
                    "Failed import of genotype for $fields[0]");
                next;
            }
            $data->{name} = $fields[2];

            # $data->{uniquename}      = $self->generate_uniquename('DSC_G');
            $data->{uniquename}
                = $self->utils->nextval( 'genotype', 'DSC_G' );
            $data->{type_id} = $genotype_type_id;
            $data->{stock_genotypes} = [ { stock_id => $stock_id } ];
            push @stock_data, $data;
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 3 - scalar @stock_data;
    if ( $self->schema->resultset('Genetic::Genotype')
        ->populate( \@stock_data ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " genotype entries. Missed $missed entries" );
    }
    return;
}

sub import_phenotype {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load strain data first!"
        if !$self->utils->is_stock_loaded('strain');
    croak "Please load Dicty Phenotypes ontology!"
        if !$self->utils->is_ontology_loaded('Dicty Phenotypes');
    croak "Please load Dicty Environment ontology!"
        if !$self->utils->is_ontology_loaded('Dicty Environment');
    croak "Please load genotype data first!"
        if !$self->utils->is_genotype_loaded();

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my $type_id
        = $self->find_or_create_cvterm( "observation", "dicty_stockcenter" );

    my $default_pub_id
        = $self->find_pub_by_title("Dicty Stock Center Phenotyping 2003-2008")
        or croak "Dicty Phenotypes ontology reference not available";

    # my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $data;
            $data->{genotype_id}
                = $self->find_or_create_genotype( $fields[0] );
            if ( !$data->{genotype_id} ) {
                $self->logger->debug("Couldn't find genotype for $fields[0]");
                next;
            }
            $data->{phenotype_id}
                = $self->find_or_create_phenotype( $fields[1], $fields[3],
                $fields[5] );
            if ( !$data->{phenotype_id} ) {
                $self->logger->debug(
                    "Couldn't find phenotype for $fields[1]");
                next;
            }
            $data->{environment_id}
                = $self->find_or_create_environment( $fields[2] );
            if ( !$data->{environment_id} ) {
                $self->logger->debug(
                    "Couldn't find environment for $fields[2]");
                next;
            }
            $data->{type_id} = $type_id;
            $data->{pub_id}  = $self->find_pub( $fields[4] );
            if ( !$data->{pub_id} ) {
                $self->logger->debug(
                    "Couldn't find publication for $fields[4]. Using default for phenotype"
                );
                $data->{pub_id} = $default_pub_id;
            }

            # push @stock_data, $data;
            my $pst_rs = $self->schema->resultset('Genetic::Phenstatement')
                ->find_or_create($data);
            if ( !$pst_rs ) {
                $self->logger->debug(
                    'Error creating phenstatement entry for $fields[0], $fields[1]'
                );
            }
        }
    }
    $io->close();

    # my $missed = $csv->record_number() / 6 - scalar @stock_data;
    # if ( $self->schema->resultset('Genetic::Phenstatement')
    #    ->populate( \@stock_data ) )
    # {
    #    $self->logger->info( "Imported "
    #            . scalar @stock_data
    #            . " phenotype entries. Missed $missed entries" );
    # }
    return;
}

sub import_parent {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load strain data first!"
        if !$self->utils->is_stock_loaded('strain');

    my $io = IO::File->new( $input, 'r' ) or croak "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or croak "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my $stock_rel_type_id
        = $self->find_or_create_cvterm( 'is_parent_of', 'stock_relation' );

    my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $data;
            $data->{object_id} = $self->find_stock( $fields[0] );
            if ( !$data->{object_id} ) {
                $self->logger->debug(
                    "Failed import of parental strain for $fields[0]");
                next;
            }
            $data->{subject_id}
                = $self->find_stock( $fields[1] );
            if ( !$data->{subject_id} ) {
                $self->logger->debug(
                    "Couldn't find $fields[1] parental strain entry");
                next;
            }
            $data->{type_id} = $stock_rel_type_id;
            push @stock_data, $data;
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 2 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::StockRelationship')
        ->populate( \@stock_data ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " parental strain entries. Missed $missed entries" );
    }
    return;
}

sub import_plasmid {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    croak "Please load strain data first!"
        if !$self->utils->is_stock_loaded('strain');
    carp "Please load plasmid data before loading strain-plasmid!"
        if !$self->utils->is_stock_loaded('plasmid');

    my $io = IO::File->new( $input, 'r' )
        or confess "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or confess "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my $stock_rel_type_id
        = $self->find_or_create_cvterm( 'part_of', 'stock_relation' );

    my $plasmid_type_id
        = $self->find_cvterm( 'plasmid', 'dicty_stockcenter' );
    my @stock_data;
    while ( my $line = $io->getline() ) {
        if ( $csv->parse($line) ) {
            my @fields = $csv->fields();
            if ( $fields[0] !~ m/^DBS[0-9]{7}/ ) {
                $self->logger->debug(
                    "Line starts with $fields[0]. Expected DBS ID");
                next;
            }

            my $data;
            $data->{object_id} = $self->find_stock( $fields[0] );
            if ( !$data->{object_id} ) {
                $self->logger->debug(
                    "Failed import of strain-plasmid for $fields[0]");
                next;
            }
            my $stock_plasmid_id = $self->find_stock( $fields[1] );
            if ( !$stock_plasmid_id ) {
                $self->logger->debug(
                    "Couldn't find $fields[1] strain-plasmid. Creating one");

                my $stockcollection_id = 0;
                $stockcollection_id
                    = $self->find_stockcollection('Dicty Azkaban');
                if ( !$stockcollection_id ) {
                    $stockcollection_id
                        = $self->create_stockcollection( 'Dicty Azkaban',
                        $plasmid_type_id );
                }

                my $new_plasmid;
                $new_plasmid->{name} = $fields[1];
                $new_plasmid->{uniquename}
                    = $self->utils->nextval( 'stock', 'DBP' );
                $new_plasmid->{type_id}     = $plasmid_type_id;
                $new_plasmid->{description} = 'Autocreated strain-plasmid';
                $new_plasmid->{stockcollection_stocks}
                    = [ { stockcollection_id => $stockcollection_id } ];

                my $plasmid_rs = $self->schema->resultset('Stock::Stock')
                    ->find_or_create($new_plasmid);
                $stock_plasmid_id = $plasmid_rs->stock_id;
            }
            $data->{subject_id} = $stock_plasmid_id;
            $data->{type_id}    = $stock_rel_type_id;
            push @stock_data, $data;
        }
    }
    $io->close();
    my $missed = $csv->record_number() / 2 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::StockRelationship')
        ->populate( \@stock_data ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " strain-plasmid entries. Missed $missed entries" );
    }
    return;
}

1;

__END__
