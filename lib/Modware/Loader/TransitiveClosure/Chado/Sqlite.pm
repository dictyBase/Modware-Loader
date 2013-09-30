package Modware::Loader::TransitiveClosure::Chado::Sqlite;
use namespace::autoclean;
use Moose;

has 'schema' => ( is => 'rw', isa => 'Bio::Chado::Schema');
has 'logger' =>
    ( is => 'rw', isa => 'Log::Log4perl::Logger');


sub bulk_load {
    my ($self) = @_;
    my $dbh = $self->schema->storage->dbh;
    $dbh->do($self->sqlmanager->retr('delete_removed_cvtermpath'));
    my $rows = $dbh->do($self->sqlmanager->retr('insert_new_cvtermpath'));
    $self->logger->debug("loaded new $rows entries in cvtermpath");
}

sub alter_tables {

}

sub reset_tables {

}


with 'Modware::Loader::Role::WithChado';
__PACKAGE__->meta->make_immutable;
1;
