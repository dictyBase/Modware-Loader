package Modware::Loader::TransitiveClosure::Staging::Pg;
use namespace::autoclean;
use Modware::Loader::Schema::Staging::TransitiveClosure;
use Moose;
with 'Modware::Role::WithDataStash' =>
    { 'create_stash_for' => [qw/cvtermpath/] };


has 'schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    trigger => sub {
        my ( $self, $schema ) = @_;
        $schema->register_class( 'Staging::Cvtermpath' =>
                'Modware::Loader::Schema::Staging::TransitiveClosure::Cvtermpath'
        );
    }
);

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
    my $dbh = $self->schema->storage->dbh;
    $dbh->do(
        "COPY temp_cvtermpath(pathdistance,object_accession,subject_accession, type_accession,object_db_id,subject_db_id,type_db_id) FROM STDIN"
    );
    for my $row ( $self->entries_in_cvtermpath_cache ) {
        my $data = join(
            "\t",
            @${row{qw(pathdistance object_accession subject_accession type_accession object_db_id subject_db_id type_db_id)}}
        ) . "\n";
        $dbh->pg_putcopydata($data);
    }
    $dbh->pg_putcopyend;
}

# Each data row is a string with four columns
# subject type(predicate) pathdistance object
sub add_data {
    my ( $self, $data_row ) = @_;
    chomp $data_row;
    my @data = split /\t/, $data_row;

    my ( $subject_db_id, $subject_acc ) = $self->normalize_id( $data[0] );
    my ( $object_db_id,  $object_acc )  = $self->normalize_id( $data[3] );
    my ( $type_db_id,    $type_acc );
    if ( $self->has_idspace( $data[1] ) ) {
        ( $type_db_id, $type_acc ) = $self->normalize_id( $data[1] );
    }
    else {
        $type_acc = $data[1];
    }

    my $insert_hash = {
        pathdistance      => $data[2],
        object_accession  => $object_acc,
        subject_accession => $subject_acc,
        object_db_id      => $object_db_id,
        subject_db_id     => $subject_db_id,
        type_accession    => $type_acc,
        type_db_id        => $object_db_id
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
