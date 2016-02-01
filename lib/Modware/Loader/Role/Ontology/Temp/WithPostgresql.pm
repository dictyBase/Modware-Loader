package Modware::Loader::Role::Ontology::Temp::WithPostgresql;

# Other modules:
use namespace::autoclean;
use Moose::Role;
with 'Modware::Loader::Role::Ontology::Temp::Generic';

# Module implementation
#
has cache_threshold =>
    ( is => 'rw', isa => 'Int', lazy => 1, default => 4000 );

sub create_temp_statements {
    my ( $self, $storage ) = @_;
    if ( $self->app_instance->has_pg_schema ) {
        my $schema = $self->app_instance->pg_schema;
        $storage->dbh->do(qq{SET SCHEMA '$schema'});
    }
    for my $elem ( grep {/^create_table_temp/} $self->sqllib->elements ) {
        $storage->dbh->do( $self->sqllib->retr($elem) );
    }

    #$storage->dbh->do(qq{ANALYZE  cvterm});
    #$storage->dbh->do(qq{ANALYZE dbxref});
}

sub drop_temp_statements {
}

after 'load_data_in_staging' => sub {
    my ($self) = @_;
    $self->schema->storage->dbh_do(
        sub {
            my ( $storage, $dbh ) = @_;
            $dbh->do(
                q{CREATE UNIQUE INDEX uniq_name_idx ON temp_cvterm(name,  is_obsolete,  cv_id)}
            );
            #$dbh->do(
                #q{CREATE UNIQUE INDEX uniq_accession_idx ON temp_cvterm(accession)}
            #);
        }
    );

    $self->logger->debug(
        sprintf "terms:%d\tcomments:%d\tsynonyms:%d\trelationships:%d in staging tables",
        $self->entries_in_staging('TempCvterm'),
        $self->entries_in_staging('TempCvtermcomment'),
        $self->entries_in_staging('TempCvtermsynonym'),
        $self->entries_in_staging('TempCvtermRelationship')
    );
};

1;    # Magic true value required at end of module

