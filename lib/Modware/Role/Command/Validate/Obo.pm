package Modware::Role::Command::Validate::Obo;



# Other modules:
use strict;
use namespace::autoclean;
use Moose::Role;
use Modware::Loader::Response;
with 'Modware::Role::Command::WithValidationLogger';

requires 'schema';

sub validate_data {
	my ($self, $node) = @_;
	return;
}

# Module implementation
#

1;    # Magic true value required at end of module

__END__

=head1 NAME

<Modware::Role::Command::Validate::Obo> - [Run validations for obo file]


