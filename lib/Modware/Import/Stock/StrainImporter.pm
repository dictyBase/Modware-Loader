
package Modware::Import::Stock::StrainImporter;

use autodie;
use strict;

use Carp;
use Moose;
use namespace::autoclean;
use Text::CSV;

use Modware::Import::Stock::DataTransformer;

with 'Modware::Role::Stock::Import::DataStash';
with 'Modware::Role::Stock::Import::Utils';

has logger => (
    is  => 'rw',
    isa => 'Log::Log4perl::Logger'
);

has schema => ( is => 'rw', isa => 'Bio::Chado::Schema' );

sub import_stock {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    my $io = IO::File->new( $input, 'r' ) or die "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or die "Cannot use CSV: " . Text::CSV->error_diag();
    $csv->sep_char("\t");

    my $type_id
        = $self->find_or_create_cvterm( 'strain', 'dicty_stockcenter' );

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
            $strain->{description} = $self->trim( $fields[3] ) if $fields[3];
            $strain->{type_id} = $type_id;
            push @stock_data, $strain;
        }
    }
    my $missed = $csv->record_number() / 4 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::Stock')->populate( \@stock_data ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " strain entries. Missed $missed entries" );
    }
}

sub import_props {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    my $io = IO::File->new( $input, 'r' ) or die "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or die "Cannot use CSV: " . Text::CSV->error_diag();
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
    my $missed = $csv->record_number() / 3 - scalar @stock_props;
    if ( $self->schema->resultset('Stock::Stockprop')
        ->populate( \@stock_props ) )
    {
        $self->logger->info( "Imported "
                . scalar @stock_props
                . " strain property entries. Missed $missed entries" );
    }
}

sub import_inventory {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

	 die "Please load strain_inventory ontology!" if !$self->is_ontology_loaded('strain_inventory');

    my $io = IO::File->new( $input, 'r' ) or die "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or die "Cannot use CSV: " . Text::CSV->error_diag();
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
            foreach my $key ( keys $inventory ) {
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
		$rank              = $rank + 1;
    }
    my $missed = $csv->record_number() / 9 - scalar @stock_data / 9;
    if ($self->schema->resultset('Stock::Stockprop')->populate( \@stock_data )
        )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data / 9
                . " strain inventory entries. Missed $missed entries" );
    }
}

sub import_publications {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");

    my $io = IO::File->new( $input, 'r' ) or die "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or die "Cannot use CSV: " . Text::CSV->error_diag();
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
    my $missed = $csv->record_number() / 2 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::StockPub')->populate( \@stock_data )
        )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " strain publication entries. Missed $missed entries" );
    }
}

sub import_characteristics {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");
	
    my $strain_char_pub_title = 'Dicty Strain Characteristics';
    my $char_pub_id = $self->find_pub_by_title($strain_char_pub_title) or die "Pub reference for strain_characteristics ontology not found!";
	
	 die "Please load strain_characteristics ontology!" if !$self->is_ontology_loaded('strain_characteristics');
		
    my $io = IO::File->new( $input, 'r' ) or die "Cannot open file: $input";
    my $csv = Text::CSV->new( { binary => 1 } )
        or die "Cannot use CSV: " . Text::CSV->error_diag();
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
			$data->{cvterm_id} = $self->find_cvterm($fields[1], 'strain_characteristics');
            if ( !$data->{stock_id} ) {
                $self->logger->debug(
                    "Couldn't find $fields[1] in strain_characteristics ontology");
                next;
            }
			$data->{pub_id} = $char_pub_id;
			push @stock_data, $data;
		}
	}
    my $missed = $csv->record_number() / 2 - scalar @stock_data;
    if ( $self->schema->resultset('Stock::StockCvterm')->populate( \@stock_data )
        )
    {
        $self->logger->info( "Imported "
                . scalar @stock_data
                . " strain characteristics entries. Missed $missed entries" );
    }
}

sub import_genotype {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");
}

sub import_phenotype {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");
}

sub import_parent {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");
}

sub import_plasmid {
    my ( $self, $input ) = @_;
    $self->logger->info("Importing data from $input");
}

1;

__END__
