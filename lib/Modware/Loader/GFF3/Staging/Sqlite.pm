package Modware::Loader::GFF3::Staging::Sqlite;
use namespace::autoclean;
use Moose;
with 'Modware::Role::WithDataStash' =>
    { 'create_stash_for' => [qw/organism/] };

has 'schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
);

has 'logger' => ( is => 'rw', isa => 'Log::Log4perl::Logger' );
has 'organism' => (is => 'rw', does => 'Modware::Role::WithOrganism');

sub create_tables {
    my ($self) = @_;
    for my $elem ( grep {/^create_table_temp/} $self->sqlmanager->elements ) {
        $self->schema->storage->dbh->do( $self->sqlmanager->retr($elem) );
    }
}

sub drop_tables {
}

sub create_indexes {
}

sub bulk_load {
    my ($self) = @_;
}

# Each data row is a string with four columns
# subject type(predicate) pathdistance object
sub add_data {
    my ( $self, $data_row ) = @_;
}

sub count_entries_in_staging {
 
}

with 'Modware::Loader::Role::WithStaging';
with 'Modware::Loader::Role::WithChadoHelper';
__PACKAGE__->meta->make_immutable;
1;

