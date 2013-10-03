package Modware::Loader::Schema::Staging::TransitiveClosure;

package Modware::Loader::Schema::Staging::TransitiveClosure::Cvtermpath;
use strict;

use base qw/DBIx::Class::Core/;

__PACKAGE__->table('temp_cvtermpath');
__PACKAGE__->add_columns( 'pathdistance' => { data_type => 'int' } );
__PACKAGE__->add_columns(
    'object_accession' => { data_type => 'varchar', nullable => 0 } );
__PACKAGE__->add_columns(
    'subject_accession' => { data_type => 'varchar', nullable => 0 } );
__PACKAGE__->add_columns(
    'type_accession' => { data_type => 'varchar', nullable => 0 } );
__PACKAGE__->add_columns(
    'object_db_id' => { data_type => 'int', nullable => 0 } );
__PACKAGE__->add_columns(
    'subject_db_id' => { data_type => 'int', nullable => 0 } );
__PACKAGE__->add_columns(
    'type_db_id' => { data_type => 'int', nullable => 0 } );

1;

