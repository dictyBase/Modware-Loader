
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
    my $row
        = $self->schema->resultset('Stock::StockGenotype')
        ->search( { 'stock.uniquename' => $dbs_id },
        { select => 'me.genotype_id', join => 'stock' } );
    if ($row) {
        $self->set_strain_genotype( $dbs_id, $row->first );
        return $self->get_strain_genotype($dbs_id);
    }
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Import::Strain - Role for strain related methods

=head1 DESCRIPTION

=cut
