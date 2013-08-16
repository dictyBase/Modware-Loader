
package Modware::Role::Stock::Import::Plasmid;

use strict;

use File::Spec::Functions qw/catfile/;
use Moose::Role;
use namespace::autoclean;

with 'Modware::Role::Stock::Import::Commons';

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

before 'execute' => sub {
    my ($self) = @_;

    foreach my $data ( @{ $self->data } ) {

        my $set_method = "set_" . $data;
        my $get_method = "get_" . $data;
        my $has_method = "has_" . $data;

        my $infile = "plasmid_" . $data . ".txt";
        my $file_reader
            = IO::File->new( catfile( $self->data_dir, $infile ), 'r' );
        while ( my $line = $file_reader->getline ) {
            my @array = split /\t/, $line;
            $self->$set_method( $array[0], [] )
                if !$self->$has_method( $array[0] );
            if ( $data eq 'inventory' ) {
                my $inventory;
                $inventory->{location}     = $array[1];
                $inventory->{color}        = $array[2];
                $inventory->{stored_as}    = $array[3];
                $inventory->{storage_date} = $array[4];
                push $self->$get_method( $array[0] ), $inventory;
                next;
            }
            if ( $data eq 'props' ) {
                push $self->$get_method( $array[0] ),
                    { $array[1] => $array[2] };
                next;
            }
            push $self->$get_method( $array[0] ), $array[1];
        }
    }
};

1;

__END__

=head1 NAME

Modware::Role::Stock::Import::Strain - Role for strain related methods

=head1 DESCRIPTION

=cut
