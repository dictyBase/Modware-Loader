package Modware::Loader::Schema::Result::Temp::Obo;

use warnings;
use strict;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('tmpobo');

__PACKAGE__->add_columns('tmpobo_id' => {
	data_type => 'integer', 
	is_auto_increment => 1, 
	is_nullable => 0
});

__PACKAGE__->add_columns('name' => {
	data_type => 'varchar', 
	is_nullable => 0, 
});


__PACKAGE__->add_columns('id' => {
	data_type => 'varchar', 
	is_nullable => 0, 
});


__PACKAGE__->add_columns('namespace' => {
	data_type => 'varchar', 
	is_nullable => 0, 
});

__PACKAGE__->add_columns('definition' => {
	data_type => 'text', 
	is_nullable => 0, 
});

__PACKAGE__->add_columns('is_relationshiptype' => {
	data_type => 'integer', 
	is_nullable => 1, 
	default_value => 0
});

__PACKAGE__->add_columns('is_obsolete' => {
	data_type => 'integer', 
	is_nullable => 1, 
	default_value => 0
});

__PACKAGE__->set_primary_key('tmpobo_id');

1;
