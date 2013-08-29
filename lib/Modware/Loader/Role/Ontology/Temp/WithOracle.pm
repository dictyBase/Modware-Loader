package Modware::Loader::Role::Ontology::Temp::WithOracle;

use namespace::autoclean;
use Moose::Role;

with 'Modware::Loader::Role::Ontology::Temp::Generic';

has cache_threshold =>
    ( is => 'rw', isa => 'Int', lazy => 1, default => 8000 );

after 'load_data_in_staging' => sub {
    my ($self) = @_;
    $self->logger->debug(
        sprintf "terms:%d\tsynonyms:%d\trelationships:%d in staging tables",
        $self->entries_in_staging('TempCvterm'),
        $self->entries_in_staging('TempCvtermsynonym'),
        $self->entries_in_staging('TempCvtermRelationship')
    );
};

sub create_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(
        qq{
	        CREATE GLOBAL TEMPORARY TABLE temp_cvterm (
               name varchar2(1024) NOT NULL, 
               accession varchar2(256) NOT NULL, 
               is_obsolete number DEFAULT '0' NOT NULL, 
               is_relationshiptype number DEFAULT '0' NOT NULL, 
               definition varchar2(4000), 
               cmmnt varchar2(4000), 
               cv_id number NOT NULL, 
               db_id number NOT NULL
    ) ON COMMIT PRESERVE ROWS }
    );

    $storage->dbh->do(
        qq{
	        CREATE GLOBAL TEMPORARY  TABLE temp_cvterm_relationship (
               subject varchar2(256) NOT NULL, 
               object varchar2(256) NOT NULL, 
               type varchar2(256) NOT NULL, 
               subject_db_id number NOT NULL, 
               object_db_id number NOT NULL, 
               type_db_id number NOT NULL
    ) ON COMMIT PRESERVE ROWS }
    );

   $storage->dbh->do(qq{
	        CREATE GLOBAL TEMPORARY TABLE temp_cvterm_synonym (
               accession varchar2(256) NOT NULL, 
               syn varchar2(1024) NOT NULL, 
               syn_scope_id number NOT NULL, 
               db_id number NOT NULL
    ) ON COMMIT PRESERVE ROWS }
    );
}

sub drop_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(qq{TRUNCATE TABLE temp_cvterm});
    $storage->dbh->do(qq{TRUNCATE TABLE temp_cvterm_relationship});
    $storage->dbh->do(qq{TRUNCATE TABLE temp_cvterm_synonym});
    $storage->dbh->do(qq{DROP TABLE temp_cvterm});
    $storage->dbh->do(qq{DROP TABLE temp_cvterm_relationship});
    $storage->dbh->do(qq{DROP TABLE temp_cvterm_synonym});
}

1;
