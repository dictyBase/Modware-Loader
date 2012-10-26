
package Modware::Load::Command::ebiGaf2dictyChado;

use strict;

use Bio::Chado::Schema;
use Moose;
use namespace::autoclean;

extends qw/Modware::Load::Chado/;

sub execute {
    my ($self) = @_;
	
}

1;

=head1 NAME

Modware::Load::Command::ebiGaf2dictyChado - Update dicty Chado with GAF from EBI

=head1 SYNOPSIS
 
=head1 REQUIRED ARGUMENTS

=head1 OPTIONS

=head1 DESCRIPTION

Prune all the existing annotations from dicty Chado. Query EBI using the web-service for annotations for each Gene ID.
Check if the link exists between feature and annotation; if yes, populate the retrieved data.

=over

