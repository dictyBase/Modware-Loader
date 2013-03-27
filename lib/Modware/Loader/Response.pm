package Modware::Loader::Response;

use namespace::autoclean;
use Moose;


has [qw/is_error is_success/] => (
	is => 'rw', 
	isa => 'Bool', 
	default => 0, 
);

has 'message' => ( is => 'rw',  isa => 'Str');

__PACKAGE__->meta->make_immutable;

1;

