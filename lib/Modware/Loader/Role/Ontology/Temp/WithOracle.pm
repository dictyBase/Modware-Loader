package Modware::Loader::Role::Ontology::Temp::WithOracle;

use namespace::autoclean;
use Moose::Role;

with 'Modware::Loader::Role::Ontology::Temp::Generic';

has cache_threshold =>
    ( is => 'rw', isa => 'Int', lazy => 1, default => 8000 );


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
}

sub drop_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(qq{TRUNCATE TABLE temp_cvterm});
    $storage->dbh->do(qq{TRUNCATE TABLE temp_cvterm_relationship});
    $storage->dbh->do(qq{TRUNCATE TABLE temp_term_delete});
    $storage->dbh->do(qq{DROP TABLE temp_cvterm});
    $storage->dbh->do(qq{DROP TABLE temp_cvterm_relationship});
    $storage->dbh->do(qq{DROP TABLE temp_term_delete});
}

1;
