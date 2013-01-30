
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

has 'dbxref_row' => (
	is => 'rw',
	isa => 'HashRef',
	traits => [qw/Hash/],
	handles => {
		add_dbxref_row => 'set',
		get_dbxref_row => 'get',
		has_dbxref_row
	}
);

sub find_or_create_dbxref_id {
    my ( $self, $dbxref ) = @_;
    my @db_vals = split( /:/, $dbxref );
    my $rs = $self->dbxref_rs->search( { accession => $db_vals[1] } );
    if ( $rs->count > 0 ) {
        return $rs->first->dbxref_id;
    }
    my $row = $self->schema->storage->txn_do(
        sub {
            my $db_rs = $self->schema->resultset('General::Db')
                ->find_or_create( { name => { -like => "%$db_vals[0]" } } );
            $db_rs->create_related( 'dbxrefs',
                { accession => $db_vals[1] } );
        }
    );
    return $row->dbxref_id;
}

1;
