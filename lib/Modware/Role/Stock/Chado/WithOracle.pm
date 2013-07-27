
use strict;

package Modware::Role::Stock::Chado::WithOracle;

use Moose::Role;
use namespace::autoclean;

sub transform_schema {
    my ( $self, $schema ) = @_;
    my $phenotype_src = $schema->source('Phenotype::Phenotype');
    $phenotype_src->remove_column('name');
    return $phenotype_src->schema();
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Chado::WithOracle - 

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
