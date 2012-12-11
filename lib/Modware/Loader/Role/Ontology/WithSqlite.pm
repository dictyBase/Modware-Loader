package Modware::Loader::Role::Ontology::WithSqlite;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use feature qw/say/;

# Module implementation
#

has cache_threshold =>
    ( is => 'rw', isa => 'Int', lazy => 1, default => 2000 );

sub transform_schema { }

sub create_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(
        qq{
	        CREATE TABLE IF NOT EXISTS temp_cvterm (
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
	        CREATE TABLE IF NOT EXISTS temp_accession (
               accession varchar(256) NOT NULL 
    )}
    );
    $storage->dbh->do(
        qq{
	        CREATE TABLE IF NOT EXISTS temp_cvterm_relationship (
               subject varchar(256) NOT NULL, 
               object varchar(256) NOT NULL, 
               type varchar(256) NULL, 
               subject_db_id integer NOT NULL, 
               object_db_id integer NOT NULL, 
               type_db_id integer NOT NULL
    )}
    );
}

sub drop_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(qq{DELETE FROM temp_cvterm});
    $storage->dbh->do(qq{DELETE FROM temp_accession});
    $storage->dbh->do(qq{DELETE FROM temp_cvterm_relationship});
}

sub delete_non_existing_terms {
	my ($self, $storage, $dbh) = @_;
	my $data = $dbh->selectall_arrayref(
		q{
			SELECT cvterm.cvterm_id, dbxref.dbxref_id FROM cvterm
			INNER JOIN dbxref ON cvterm.dbxref_id=dbxref.dbxref_id
			LEFT JOIN temp_cvterm tmcv ON (
				tmcv.accession = dbxref.accession
				AND
				tmcv.db_id = dbxref.db_id
			)
			WHERE tmcv.accession IS NULL
			AND tmcv.db_id IS NULL
			AND cvterm.cv_id IN (SELECT cv_id FROM temp_cvterm)
			AND dbxref.db_id IN (SELECT db_id FROM temp_cvterm)
		},  {Slice => {}}
	);
	
	my $schema = $self->schema;
	for my $row(@$data) {
		$schema->resultset('Cv::Cvterm')->find($row->{cvterm_id})->delete;
		$schema->resultset('General::Dbxref')->find($row->{dbxref_id})->delete;
	}
	return scalar @$data;
}

sub create_dbxrefs {
    my ( $self, $storage, $dbh ) = @_;
    $dbh->do(
        q{
    		INSERT INTO temp_accession(accession)
			SELECT tmcv.accession FROM temp_cvterm tmcv
			LEFT JOIN dbxref ON (
			     tmcv.accession = dbxref.accession
			     AND
			     tmcv.db_id = dbxref.db_id
            )
			WHERE dbxref.accession is NULL
			AND 
			dbxref.db_id IS NULL
			}
    );
    my $rows = $dbh->do(
        q{
			INSERT INTO dbxref(accession, db_id)
			SELECT tmcv.accession, tmcv.db_id FROM temp_cvterm tmcv
			LEFT JOIN dbxref ON (
			     tmcv.accession = dbxref.accession
			     AND
			     tmcv.db_id = dbxref.db_id
            )
			WHERE dbxref.accession is NULL
			AND 
			dbxref.db_id IS NULL
			}
    );
    return $rows;
}

sub create_cvterms {
    my ( $self, $storage, $dbh ) = @_;
    my $rows = $dbh->do(
        q{
    		INSERT INTO cvterm(name, is_obsolete, is_relationshiptype,
    		  definition, cv_id, dbxref_id)
			SELECT tmcv.name,tmcv.is_obsolete,tmcv.is_relationshiptype, 
			tmcv.definition,tmcv.cv_id,dbxref.dbxref_id 
			FROM temp_cvterm tmcv
			INNER JOIN temp_accession tmacc ON 
			     tmcv.accession=tmacc.accession
			INNER JOIN dbxref ON (
			  dbxref.accession=tmcv.accession
			  AND dbxref.db_id=tmcv.db_id
			)
			}
    );
    return $rows;
}

sub create_cvterms_debug {
    my ( $self, $storage, $dbh ) = @_;
    my $data = $dbh->selectall_arrayref(
        q{
			SELECT tmcv.name,tmcv.is_obsolete,tmcv.is_relationshiptype, 
			tmcv.definition,tmcv.cv_id,dbxref.dbxref_id 
			FROM temp_cvterm tmcv
			INNER JOIN temp_accession tmacc ON 
			     tmcv.accession=tmacc.accession
			INNER JOIN dbxref ON (
			  dbxref.accession=tmcv.accession
			  AND dbxref.db_id=tmcv.db_id
			)
			}, { Slice => {} }
    );
    for my $row (@$data) {
        $self->schema->resultset('Cv::Cvterm')->create($row);
    }
    return scalar @$data;
}

sub update_cvterm_names {
    my ( $self, $storage, $dbh ) = @_;

#SQLite do not support JOINS in update statements,  so it's need to be done in few
#more steps
#This will update the name of cvterms.
    my $data = $dbh->selectall_arrayref(
        q{
    	SELECT fresh.* FROM (
    	   SELECT tmcv.name fname, cvterm.name oname, cvterm.cvterm_id
    		 FROM cvterm
    		 INNER JOIN dbxref ON dbxref.dbxref_id = cvterm.dbxref_id
    		 INNER JOIN temp_cvterm tmcv ON (
    		 	dbxref.accession = tmcv.accession
    		 	AND 
    		 	dbxref.db_id = tmcv.db_id
    		 )
    	) AS fresh
    	WHERE fresh.fname != fresh.oname
    }, { Slice => {} }
    );
    for my $frow (@$data) {
        $self->logger->info(
            sprintf( "old:%s\tnew:%s", $frow->{oname}, $frow->{fname} ) );
        my $dbrow
            = $self->schema->resultset('Cv::Cvterm')
            ->find( $frow->{cvterm_id} )
            ->update( { name => $frow->{fname} } );
    }
    return scalar @$data;
}

sub update_cvterms {
    my ( $self, $storage, $dbh ) = @_;

# This will update definition and status of all cvterms, as usual it is more work in case
# of SQLite existing cvterms
    my $data = $dbh->selectall_arrayref(
        q{
    		SELECT cvterm.cvterm_id, cvterm.name, tmcv.definition, tmcv.is_obsolete 
    		 FROM cvterm
    		 INNER JOIN dbxref ON dbxref.dbxref_id = cvterm.dbxref_id
    		 INNER JOIN temp_cvterm tmcv ON (
    		 	dbxref.accession = tmcv.accession
    		 	AND 
    		 	dbxref.db_id = tmcv.db_id
    		 )
    	}, { Slice => {} }
    );
    for my $trow (@$data) {
        $self->schema->resultset('Cv::Cvterm')->find( $trow->{cvterm_id} )
            ->update(
            {   definition  => $trow->{definition},
                is_obsolete => $trow->{is_obsolete}
            }
            );
    }
    return scalar @$data;
}

sub merge_comments {
    return 0;
}

sub create_relations {
    my ( $self, $storage, $dbh ) = @_;
    my $rows = $dbh->do(
        q{
        INSERT INTO cvterm_relationship(object_id, subject_id, type_id)
		SELECT object.cvterm_id, subject.cvterm_id, type.cvterm_id
        FROM temp_cvterm_relationship tmprel

        INNER JOIN dbxref dbobject ON (
        	dbobject.accession = tmprel.object AND
        	dbobject.db_id = tmprel.object_db_id 
        )
        INNER JOIN cvterm object ON
        object.dbxref_id = dbobject.dbxref_id

        INNER JOIN dbxref dbsubject ON (
        	dbsubject.accession = tmprel.subject AND
        	dbsubject.db_id = tmprel.subject_db_id 
        )
        INNER JOIN cvterm subject ON
        subject.dbxref_id = dbsubject.dbxref_id

        INNER JOIN dbxref dbtype ON (
        	dbtype.accession = tmprel.type AND
        	dbtype.db_id = tmprel.type_db_id 
        )
        INNER JOIN cvterm type ON
        type.dbxref_id = dbtype.dbxref_id
             
      EXCEPT
      SELECT cvrel.object_id, cvrel.subject_id, cvrel.type_id
      FROM cvterm_relationship cvrel
    }
    );
    return $rows;
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Loader::Role::Chado::BCS::Engine::Oracle

