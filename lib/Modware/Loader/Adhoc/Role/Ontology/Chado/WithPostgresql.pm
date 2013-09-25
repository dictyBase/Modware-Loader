package Modware::Loader::Adhoc::Role::Ontology::Chado::WithPostgresql;

use namespace::autoclean;
use Moose::Role;

sub transform_schema {
    my ( $self, $schema ) = @_;
    if ( my $name = $self->app_instance->pg_schema ) {
        $schema->storage->dbh->do(qq{SET SCHEMA '$name'});
    }
}

1;    # Magic true value required at end of module

