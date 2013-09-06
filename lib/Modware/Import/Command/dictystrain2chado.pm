
package Modware::Import::Command::dictystrain2chado;

use strict;

use Data::Dumper;
use Moose;
use namespace::autoclean;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Import::Strain';

has 'prune' => ( is => 'rw', isa => 'Bool', default => 0 );

has data => (
    is  => 'rw',
    isa => 'ArrayRef',
    default =>

        # sub { [qw/characteristics publications inventory genotype props/] }
        sub { [qw/genotype phenotype/] }
);

has mock_pub => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

sub execute {

    my ($self) = @_;

    my $guard = $self->schema->txn_scope_guard;

    if ( $self->mock_pub ) {
        $self->_mock_publications();
    }

    if ( $self->prune ) {
        $self->schema->storage->dbh_do(
            sub {
                my ( $storage, $dbh ) = @_;
                my $sth;
                for my $table (
                    qw/stock stockprop stock_cvterm stock_pub stock_genotype genotype phenotype environment/
                    )
                {
                    $sth = $dbh->prepare(qq{DELETE FROM $table});
                    $sth->execute;
                }
                $sth->finish;
            }
        );
    }

    my $type_id = $self->schema->resultset('Cv::Cvterm')
        ->search( { name => 'strain' }, {} )->first->cvterm_id;

    my $io = IO::File->new( $self->input, 'r' );
    my $hash;

    while ( my $line = $io->getline ) {
        my @cols = split( /\t/, $line );
        $hash->{uniquename}  = $cols[0] if $cols[0] =~ /^DBS[0-9]{7}/;
        $hash->{name}        = $cols[1];
        $hash->{organism_id} = $self->find_or_create_organism( $cols[2] )
            if $cols[2];
        $hash->{description} = $self->trim( $cols[3] );
        $hash->{type_id}     = $type_id;

        my $stock_rs
            = $self->schema->resultset('Stock::Stock')->find_or_create($hash);

        my $strain_char_pub_title = 'Dicty Strain Characteristics';
        my $char_pub_id = $self->find_pub_by_title($strain_char_pub_title);

        if ( $self->has_characteristics( $hash->{uniquename} ) ) {
            if ($char_pub_id) {
                foreach my $characteristics (
                    @{ $self->get_characteristics( $hash->{uniquename} ) } )
                {
                    my $char_cvterm_id = $self->find_cvterm(
                        $self->trim($characteristics),
                        "strain_characteristics"
                    );
                    $stock_rs->create_related(
                        'stock_cvterms',
                        {   cvterm_id => $char_cvterm_id,
                            pub_id  => $char_pub_id
                        }
                    );
                }
            }
            else {
                $self->logger->warn(
                    "Strain characteristics cannot be loaded. Required reference missing"
                );
            }
        }
        else {
            $self->logger->warn(
                "Strain characteristics cannot be loaded. Required reference missing"
            );
        }

        if ( $self->has_publications( $hash->{uniquename} ) ) {
            foreach my $pmid (
                @{ $self->get_publications( $hash->{uniquename} ) } )
            {
                my $pub_id = $self->find_pub($pmid);
                if ($pub_id) {
                    $stock_rs->create_related( 'stock_pubs',
                        { pub_id => $pub_id } );
                }
                else {
                    $self->logger->warn(
                        "Reference does not exist for PMID:$pmid");
                }
            }
        }

        if ( $self->has_inventory( $hash->{uniquename} ) ) {
            my $rank = 0;
            foreach my $inventory (
                @{ $self->get_inventory( $hash->{uniquename} ) } )
            {
                foreach my $key ( keys $inventory ) {
                    my $type = $key;
                    $type =~ s/_/ /g if $type =~ /_/;

                    $stock_rs->create_related(
                        'stockprops',
                        {   type_id => $self->find_cvterm(
                                $type, 'strain_inventory'
                            ),
                            value => $self->trim( $inventory->{$key} ),
                            rank  => $rank
                        }
                    ) if $inventory->{$key};
                }
                $rank = $rank + 1;
            }
        }

        if ( $self->has_genotype( $hash->{uniquename} ) ) {
            my $genotype = @{ $self->get_genotype( $hash->{uniquename} ) }[0];
            my ( $key, $value ) = each %{$genotype};
            my $genotype_type_id
                = $self->find_cvterm( 'genotype', 'dicty_stockcenter' );
            my $genotype_rs
                = $self->schema->resultset('Genetic::Genotype')
                ->find_or_create(
                {   name       => $self->trim($value),
                    uniquename => $self->trim($key),
                    type_id    => $genotype_type_id
                }
                );
            $stock_rs->create_related( 'stock_genotypes',
                { genotype_id => $genotype_rs->genotype_id } );
        }

        if ( $self->has_props( $hash->{uniquename} ) ) {
            my $rank;
            my $previous_type = '';
            my @props         = @{ $self->get_props( $hash->{uniquename} ) };
            foreach my $prop (@props) {
                my ( $key, $value ) = each %{$prop};
                $rank = 0 if $previous_type ne $key;
                my $props_type_id
                    = $self->find_cvterm( $key, "dicty_stockcenter" );
                $stock_rs->create_related(
                    'stockprops',
                    {   type_id => $props_type_id,
                        value   => $self->trim($value),
                        rank    => $rank
                    }
                );
                $rank          = $rank + 1;
                $previous_type = $key;
            }
        }

        if ( $self->has_phenotype( $hash->{uniquename} ) ) {
            my @phenotype_data = $self->get_phenotype( $hash->{uniquename} );
            for my $i ( 0 .. scalar(@phenotype_data) - 1 ) {
                my $phenotype_term  = $phenotype_data[$i][0];
                my $phenotype_env   = $phenotype_data[$i][1];
                my $phenotype_assay = $phenotype_data[$i][2];
                my $phenotype_pmid  = $self->trim( $phenotype_data[$i][3] );

                my $env_id = $self->find_or_create_environment($phenotype_env)
                    if $phenotype_env;

                my $phenotype_id
                    = $self->find_or_create_phenotype( $hash->{uniquename},
                    $phenotype_term, $phenotype_assay )
                    if $phenotype_term;

                my $genotype_id = $self->find_genotype( $hash->{uniquename} );
                if ( !$genotype_id ) {
                    $self->logger->warn(
                        "Genotype NOT found for $hash->{uniquename}");
                }

                my $type_id = $self->find_or_create_cvterm( "unspecified",
                    "Dicty Phenotypes" );

                my $pub_id = $self->find_pub_by_title(
                    "Dicty Stock Center Phenotyping 2003-2008");

                if ( $genotype_id and $phenotype_id and $env_id and $type_id )
                {
                    $self->schema->resultset('Genetic::Phenstatement')
                        ->find_or_create(
                        {   genotype_id    => $genotype_id,
                            phenotype_id   => $phenotype_id,
                            environment_id => $env_id,
                            type_id        => $type_id,
                            pub_id         => $pub_id
                        }
                        );
                }
            }
        }

    }

    $guard->commit;
    $self->schema->storage->disconnect;

    return;
}

1;

__END__

=head1 NAME

Modware::Import::Command::dictystrain2chado - Command to import strain data from dicty stock 

=head1 VERSION
=head1 SYNOPSIS
=head1 DESCRIPTION
=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT
=cut
