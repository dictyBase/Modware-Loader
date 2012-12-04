package Modware::Loader::Role::Ontology::WithSqlite;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use feature qw/say/;
use Data::Dump qw/dump/;

# Module implementation
#

has cache_threshold =>
    ( is => 'rw', isa => 'Int', lazy => 1, default => 2000 );

sub transform_schema { }

sub create_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(
        qq{
	        CREATE TEMPORARY TABLE temp_cvterm (
               name varchar(1024) NOT NULL, 
               accession varchar(1024) NOT NULL, 
               is_obsolete integer NOT NULL DEFAULT 0, 
               is_relationshiptype integer NOT NULL DEFAULT 0, 
               definition text, 
               comment text, 
               cv_id integer NOT NULL, 
               db_id integer NOT NULL
    )}
    );

    $storage->dbh->do(
        qq{
	        CREATE TEMPORARY TABLE temp_cvterm_relationship (
               subject varchar(1024) NOT NULL, 
               object varchar(1024) NOT NULL, 
               type varchar(256) NOT NULL 
    )}
    );
}

sub drop_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(qq{DROP TABLE temp_cvterm });
    $storage->dbh->do(qq{DROP TABLE temp_cvterm_relationship });
}

sub merge_dbxrefs {
    my ( $self, $storage, $dbh ) = @_;
    my $rows = $dbh->do(
        q{
			INSERT INTO dbxref(accession, db_id)
			SELECT tmcv.accession, tmcv.db_id FROM temp_cvterm tmcv
			LEFT JOIN dbxref ON tmcv.accession=dbxref.accession
			LEFT JOIN db ON db.db_id = tmcv.db_id
			WHERE dbxref.accession is NULL
			AND db.db_id is NULL
			}
    );
    return $rows;
}

sub merge_cvterms {
    my ( $self, $storage, $dbh , @args) = @_;
    my $rows = $dbh->do(
        q{
			INSERT INTO cvterm(name, is_obsolete, is_relationshiptype, 
			  definition, cv_id, dbxref_id)
			SELECT tmcv.name, tmcv.is_obsolete,  tmcv.is_relationshiptype, 
			tmcv.definition, tmcv.cv_id,dbxref.dbxref_id 
			FROM temp_cvterm tmcv
			LEFT JOIN cvterm ON cvterm.name=tmcv.name
			INNER JOIN dbxref ON dbxref.accession=tmcv.accession
			INNER JOIN db ON db.db_id=tmcv.db_id
			WHERE cvterm.name is NULL
			AND cvterm.cv_id = ?
			},  undef , @args
    );
    return $rows;
}

sub merge_comments {
    return 0;
}

sub merge_relations {
    my ( $self, $storage, $dbh , $arg) = @_;
    my $rows = $dbh->do(q{
    	INSERT INTO cvterm_relationship(object_id, subject_id, type_id)
    	SELECT object.cvterm_id, subject.cvterm_id, type.cvterm_id
    	FROM temp_cvterm_relationship tmprel
    	INNER JOIN cvterm object ON
    	  tmprel.object = object.name
		INNER JOIN cvterm subject ON
		  tmprel.subject = subject.name
		INNER JOIN cvterm type ON
		  tmprel.type = type.name
		 EXCEPT
    	SELECT cvrel.object_id, cvrel.subject_id, cvrel.type_id
    	FROM cvterm_relationship cvrel
    	INNER JOIN cvterm object ON
    	  cvrel.object_id = object.cvterm_id
    	INNER JOIN cvterm subject ON
    	   cvrel.subject_id = subject.cvterm_id
    	INNER JOIN cvterm type ON
    	   cvrel.type_id = type.cvterm_id
    	WHERE object.cv_id = ?
    	 AND subject.cv_id = ?
    	 AND type.cv_id = ?
    }, undef,  ($arg, $arg, $arg));
    return $rows;
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Loader::Role::Chado::BCS::Engine::Oracle

