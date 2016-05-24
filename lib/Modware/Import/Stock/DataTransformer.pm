
package Modware::Import::Stock::DataTransformer;

use strict;

use Moose;
use namespace::autoclean;

sub convert_row_to_strain_inventory_hash {
    my ( $self, @array ) = @_;
    my $inventory;
    $inventory->{location}        = $array[1];
    $inventory->{color}           = $array[2];
    $inventory->{'number of vials'} = $array[3];
    $inventory->{'obtained as'}     = $array[4];
    $inventory->{'stored as'}       = $array[5];
    $inventory->{'storage date'}    = $array[6];
    $inventory->{'private comment'} = $array[7];
    $inventory->{'public comment'}  = $array[8];
    return $inventory;
}

sub convert_row_to_plasmid_inventory_hash {
    my ( $self, @array ) = @_;
    my $inventory;
    $inventory->{location}       = $array[1];
    $inventory->{color}          = $array[2];
    $inventory->{stored_as}      = $array[3];
    $inventory->{storage_date}   = $array[4];
    $inventory->{public_comment} = $array[5];
    return $inventory;
}

1;

__END__
