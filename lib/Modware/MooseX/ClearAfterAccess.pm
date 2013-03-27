package Modware::MooseX::ClearAfterAccess;

use namespace::autoclean;
use Moose ();
use Moose::Exporter;

Moose::Exporter->setup_import_methods(
	trait_aliases => [
		'Modware::Meta::Attribute::Trait::ClearAfterAccess'
	]
);



1;    # Magic true value required at end of module

package Moose::Meta::Attribute::Custom::Trait::ClearAfterAccess;

sub register_implementation {
 return 'Modware::Meta::Attribute::Trait::ClearAfterAccess';
}

1;
