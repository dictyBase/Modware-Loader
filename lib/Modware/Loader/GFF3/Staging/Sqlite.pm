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
    my ($self) = @_;
    $self->schema->storage->dbh->do(
        $self->sqlmanager->retr('drop_table_temp_cvtermpath') );
}

sub create_indexes {
}

sub bulk_load {
    my ($self) = @_;
    $self->schema->resultset('Staging::Cvtermpath')
        ->populate( [ $self->entries_in_cvtermpath_cache ] );
}

# Each data row is a string with four columns
# subject type(predicate) pathdistance object
sub add_data {
    my ( $self, $data_row ) = @_;
    chomp $data_row;
    my @data = split /\t/, $data_row;

    my ( $subject_db_id, $subject_acc ) = $self->normalize_id( $data[0] );
    my ( $object_db_id,  $object_acc )  = $self->normalize_id( $data[3] );
    my ($type_acc);
    if ( $self->has_idspace( $data[1] ) ) {
        my @parsed = $self->parse_id( $data[1] );
        $type_acc = $parsed[1];
    }
    else {
        $type_acc = $data[1];
    }

    my $type_db_id
        = $self->has_namespace
        ? $self->find_or_create_dbrow( $self->namespace )->db_id
        : $object_db_id;

    my $insert_hash = {
        pathdistance      => $data[2],
        object_accession  => $object_acc,
        subject_accession => $subject_acc,
        object_db_id      => $object_db_id,
        subject_db_id     => $subject_db_id,
        type_accession    => $type_acc,
        type_db_id        => $type_db_id
    };
    $self->add_to_cvtermpath_cache($insert_hash);
}

sub count_entries_in_staging {
    my ($self) = @_;
    my $counts;
    my $schema = $self->schema;
    for my $name ( grep {/^Staging/} $schema->sources ) {
        $counts->{ $schema->source($name)->from }
            = $schema->resultset($name)->count( {} );
    }
    return $counts;
}

with 'Modware::Loader::Role::WithStaging';
with 'Modware::Loader::Role::WithChadoHelper';
__PACKAGE__->meta->make_immutable;
1;

