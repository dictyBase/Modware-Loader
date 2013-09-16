
use strict;

package Modware::Role::Stock::Import::Strain;

use File::Spec::Functions qw/catfile/;
use Moose::Role;
use namespace::autoclean;

with 'Modware::Role::Stock::Import::Commons';
with 'Modware::Role::Stock::Import::Strain::Phenotype';

has '_characteristics' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_characteristics => 'set',
        get_characteristics => 'get',
        has_characteristics => 'defined'
    }
);

has '_publications' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_publications => 'set',
        get_publications => 'get',
        has_publications => 'defined'
    }
);

has '_inventory' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_inventory => 'set',
        get_inventory => 'get',
        has_inventory => 'defined'
    }
);

has '_genotype' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_genotype => 'set',
        get_genotype => 'get',
        has_genotype => 'defined'
    }
);

has '_props' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_props => 'set',
        get_props => 'get',
        has_props => 'defined'
    }
);

has '_phenotype' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_phenotype => 'set',
        get_phenotype => 'get',
        has_phenotype => 'defined'
    }
);

has '_parent' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_parent => 'set',
        get_parent => 'get',
        has_parent => 'defined'
    }
);

has '_plasmid' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_plasmid => 'set',
        get_plasmid => 'get',
        has_plasmid => 'defined'
    }
);

before 'execute' => sub {
    my ($self) = @_;

    foreach my $data ( @{ $self->data } ) {

        my $set_method = "set_" . $data;
        my $get_method = "get_" . $data;
        my $has_method = "has_" . $data;

        my $infile = "strain_" . $data . ".txt";
        my $file_reader
            = IO::File->new( catfile( $self->data_dir, $infile ), 'r' );
        while ( my $line = $file_reader->getline ) {
            my @array = split /\t/, $line;
            $self->$set_method( $array[0], [] )
                if !$self->$has_method( $array[0] );
            if ( $data eq 'inventory' ) {
                my $inventory;
                $inventory->{location}        = $array[1];
                $inventory->{color}           = $array[2];
                $inventory->{number_of_vials} = $array[3];
                $inventory->{obtained_as}     = $array[4];
                $inventory->{stored_as}       = $array[5];
                $inventory->{storage_date}    = $array[6];
                $inventory->{private_comment} = $array[7];
                $inventory->{public_comment}  = $array[8];
                push $self->$get_method( $array[0] ), $inventory;
                next;
            }
            if ( $data eq 'genotype' or $data eq 'props' ) {
                push $self->$get_method( $array[0] ),
                    { $array[1] => $array[2] };
                next;
            }
            if ( $data eq 'phenotype' ) {
                my @row;
                for my $position ( 1, 2, 3, 4 ) {
                    push @row, $array[$position];
                }
                push $self->$get_method( $array[0] ), @row;
                next;
            }
            push $self->$get_method( $array[0] ), $array[1];
        }
    }

    if ( $self->dsc_phenotypes ) {
        my $file_reader
            = IO::File->new( catfile( 'share', 'DSC_phenotypes.tsv' ), 'r' );
        while ( my $line = $file_reader->getline ) {
            my @array = split /\t/, $line;
            $self->set_phenotype( $array[0], [] )
                if !$self->has_phenotype( $array[0] );
            my @row;
            push @row, $array[2];
            push @row, $array[5];
            push @row, $array[3];
            push $self->get_phenotype( $array[0] ), @row;
        }
    }
};

has '_strain_genotype' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_strain_genotype => 'set',
        get_strain_genotype => 'get',
        has_strain_genotype => 'defined'
    }
);

sub find_genotype {
    my ( $self, $dbs_id ) = @_;
    if ( $self->has_strain_genotype($dbs_id) ) {
        return $self->get_strain_genotype($dbs_id)->genotype_id;
    }

    my $stock_rs
        = $self->schema->resultset('Stock::Stock')
        ->search( { uniquename => $dbs_id }, {} );
    my $row = $stock_rs->related_resultset('stock_genotypes');
    if ( $row->count > 0 ) {
        $self->set_strain_genotype( $dbs_id, $row->first );
        return $self->get_strain_genotype($dbs_id)->genotype_id;
    }
}

has _curr_genotype_uniquename => (
    is  => 'rw',
    isa => 'Str'
);

sub generate_genotype_uniquename {
    my ($self) = @_;
    if ( !$self->_curr_genotype_uniquename ) {
        my $genotype_uniquename_rs
            = $self->schema->resultset('Genetic::Genotype')->search(
            {},
            {   select   => 'uniquename',
                order_by => { -desc => 'uniquename' }
            }
            );
        if ( $genotype_uniquename_rs->count > 0 ) {
            print $genotype_uniquename_rs->single->uniquename . "\n";
            $self->_curr_genotype_uniquename(
                $genotype_uniquename_rs->single->uniquename );
        }
        else {
            $self->_curr_genotype_uniquename( sprintf "DSC_G%07d", 0 );
        }
    }
    ( my $new_genotype_uniquename = $self->_curr_genotype_uniquename )
        =~ s/^DSC_G[0]{1,6}//;
    $self->_curr_genotype_uniquename( sprintf "DSC_G%07d",
        $new_genotype_uniquename + 1 );
    return $self->_curr_genotype_uniquename;
}

sub find_or_create_genotype {
    my ( $self, $dbs_id ) = @_;
    return if $self->find_genotype($dbs_id);

    my $genotype_uniquename = $self->generate_genotype_uniquename();
    my $stock_rs            = $self->get_stock_row($dbs_id);
    my $genotype_rs
        = $self->schema->resultset('Genetic::Genotype')->find_or_create(
        {   name       => $stock_rs->name,
            uniquename => $genotype_uniquename,
            type_id => $self->find_cvterm( 'genotype', 'dicty_stockcenter' )
        }
        );
    my $stock_genotype_rs
        = $stock_rs->find_or_create_related( 'stock_genotypes',
        { genotype_id => $genotype_rs->genotype_id } );
    $self->set_strain_genotype( $dbs_id, $stock_genotype_rs );
    return $self->get_strain_genotype($dbs_id)->genotype_id;
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Import::Strain - Role for strain related methods

=head1 DESCRIPTION

=cut
