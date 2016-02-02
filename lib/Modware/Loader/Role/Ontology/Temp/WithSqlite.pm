package Modware::Loader::Role::Ontology::Temp::WithSqlite;

use namespace::autoclean;
use Moose::Role;
with 'Modware::Loader::Role::Ontology::Temp::Generic';

has cache_threshold =>
    ( is => 'rw', isa => 'Int', lazy => 1, default => 4000 );

after 'load_data_in_staging' => sub {
    my ($self) = @_;
    $self->schema->storage->dbh_do(
        sub {
            my ( $storage, $dbh ) = @_;
            $dbh->do(
                q{CREATE UNIQUE INDEX uniq_name_idx ON temp_cvterm(name,  is_obsolete,  cv_id)}
            );
            $dbh->do(
                q{CREATE UNIQUE INDEX uniq_accession_idx ON temp_cvterm(accession)}
            );
        }
    );

    $self->logger->debug(
        sprintf
            "terms:%d\tsynonyms:%d\tcomments:%d\trelationships:%d in staging tables",
        $self->entries_in_staging('TempCvterm'),
        $self->entries_in_staging('TempCvtermsynonym'),
        $self->entries_in_staging('TempCvtermcomment'),
        $self->entries_in_staging('TempCvtermRelationship')
    );
};

sub create_temp_statements {
    my ( $self, $storage ) = @_;
    for my $elem ( grep {/^create_table_temp/} $self->sqllib->elements ) {
        $storage->dbh->do( $self->sqllib->retr($elem) );
    }
}

sub drop_temp_statements {
}

1;
