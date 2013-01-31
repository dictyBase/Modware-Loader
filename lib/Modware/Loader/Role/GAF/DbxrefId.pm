
use strict;

package Modware::Loader::Role::GAF::DbxrefId;

use Moose::Role;

has 'dbxref_rs' => (
    is      => 'ro',
    isa     => 'DBIx::Class::ResultSet',
    default => sub {
        my ($self) = @_;
        return $self->schema->resultset('General::Dbxref')->search(
            {},
            {   cache  => 1,
                select => [qw/dbxref_id accession/],
            }
        );
    },
    lazy => 1
);

has 'dbrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_dbrow    => 'set',
        get_dbrow    => 'get',
        delete_dbrow => 'delete',
        has_dbrow    => 'defined'
    }
);

has 'dbxref_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_dbxref_row    => 'set',
        get_dbxref_row    => 'get',
        delete_dbxref_row => 'delete',
        has_dbxref_row    => 'defined'
    }
);

sub find_or_create_db_id {
    my ( $self, $name ) = @_;
    if ( $self->has_dbrow($name) ) {
        return $self->get_dbrow($name)->db_id;
    }
    my $schema = $self->schema;
    my $row    = $schema->resultset('General::Db')
        ->find_or_create( { name => $name } );
    $self->set_dbrow( $name, $row );
    $row->db_id;
}

sub find_or_create_dbxref_id {
    my ( $self, $dbxref ) = @_;
    my @db_vals = split( /:/, $dbxref );

    if ( $self->has_dbxref_row( $db_vals[1] ) ) {
        return $self->get_dbxref_row( $db_vals[1] )->dbxref_id;
    }
    my $schema = $self->schema;
    my $row = $self->dbxref_rs->search( { accession => $db_vals[1] } );
    if ( $row->count > 0 ) {
        $self->set_dbxref_row( $db_vals[1], $row->first );
        return $self->get_dbxref_row( $db_vals[1] )->dbxref_id;
    }
    else {
        my $new_dbxref_row = $schema->resultset('General::Dbxref')->create(
            {   accession => $db_vals[1],
                db_id     => $self->find_or_create_db_id( $db_vals[0] )
            }
        );
        $self->set_dbxref_row( $db_vals[1], $new_dbxref_row );
        return $self->get_dbxref_row( $db_vals[1] )->dbxref_id;
    }
}

1;
