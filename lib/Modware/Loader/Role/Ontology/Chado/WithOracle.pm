package Modware::Loader::Role::Ontology::Chado::WithOracle;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use feature qw/say/;

# Module implementation
#



sub transform_schema {
    my ($self, $schema) = @_;
    my $source = $schema->source('Cv::Cvtermsynonym');
    $source->remove_column('synonym');
    $source->add_column(
        'synonym_' => {
            data_type   => 'varchar',
            is_nullable => 0,
            size        => 1024
        }
    );

    my $cvterm_source = $schema->source('Cv::Cvterm');
    $cvterm_source->remove_column('definition');
    $cvterm_source->add_column(
        'definition' => {
            data_type   => 'clob',
            is_nullable => 1
        }
    );

    my @sources = (
        'Cv::Cvprop',     'Cv::Cvtermprop',
        'Cv::Dbxrefprop', 'Sequence::Featureprop',
        'Sequence::FeatureCvtermprop'
    );
    for my $name (@sources) {
        my $result_source = $schema->source($name);
        next if !$result_source->has_column('value');
        $result_source->remove_column('value');
        $result_source->add_column(
            'value' => {
                data_type   => 'clob',
                is_nullable => 1
            }
        );
    }
}

sub after_loading_in_staging {
    my ( $self, $storage, $dbh ) = @_;
#    $dbh->do(
#        q{CREATE UNIQUE INDEX uniq_name_idx ON temp_cvterm(name,  is_obsolete,  cv_id)}
#    );
#    $dbh->do(
#        q{CREATE UNIQUE INDEX uniq_accession_idx ON temp_cvterm(accession)});
}

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
	        CREATE GLOBAL TEMPORARY TABLE temp_accession (
               accession varchar2(256) NOT NULL 
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
    $storage->dbh->do(qq{TRUNCATE TABLE temp_accession});
    $storage->dbh->do(qq{TRUNCATE TABLE temp_cvterm_relationship});
    $storage->dbh->do(qq{TRUNCATE TABLE temp_term_delete});
    $storage->dbh->do(qq{DROP TABLE temp_cvterm});
    $storage->dbh->do(qq{DROP TABLE temp_accession});
    $storage->dbh->do(qq{DROP TABLE temp_cvterm_relationship});
    $storage->dbh->do(qq{DROP TABLE temp_term_delete});
}

sub delete_non_existing_terms {
    my ( $self, $storage, $dbh ) = @_;
    $dbh->do(
        q{
			CREATE GLOBAL TEMPORARY TABLE temp_term_delete 
			 ON COMMIT PRESERVE ROWS AS
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
	     }
    );

    $dbh->do(
        q{ DELETE FROM cvterm WHERE cvterm.cvterm_id IN( SELECT cvterm_id FROM
        temp_term_delete )}
    );
    my $rows = $dbh->do(
        q{ DELETE FROM dbxref  WHERE dbxref.dbxref_id IN (SELECT dbxref_id FROM
        temp_term_delete)}
    );
    return $rows;
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
    my $row = $dbh->do(
        q{
    	MERGE INTO cvterm USING (
    	   SELECT tmcv.name fname, cvterm.name oname, cvterm.cvterm_id
    		 FROM cvterm
    		 INNER JOIN dbxref ON dbxref.dbxref_id = cvterm.dbxref_id
    		 INNER JOIN temp_cvterm tmcv ON (
    		 	dbxref.accession = tmcv.accession
    		 	AND 
    		 	dbxref.db_id = tmcv.db_id
    		 )
    	) fresh
    	ON (cvterm.cvterm_id = fresh.cvterm_id)
    	WHEN MATCHED THEN UPDATE 
    	  SET cvterm.name = fresh.fname
    	  WHERE fresh.fname != fresh.oname
    });
    return  $row;
}

sub update_cvterms {
    my ( $self, $storage, $dbh ) = @_;
    my $row = $dbh->do(
        q{
            MERGE INTO cvterm USING (
    		SELECT cvterm.cvterm_id, tmcv.definition, tmcv.is_obsolete 
    		 FROM cvterm
    		 INNER JOIN dbxref ON dbxref.dbxref_id = cvterm.dbxref_id
    		 INNER JOIN temp_cvterm tmcv ON (
    		 	dbxref.accession = tmcv.accession
    		 	AND 
    		 	dbxref.db_id = tmcv.db_id
    		 ) ) eterm
    		  ON (cvterm.cvterm_id = eterm.cvterm_id)
    		  WHEN MATCHED THEN UPDATE 
    		  	SET cvterm.is_obsolete = eterm.is_obsolete, 
    		  	    cvterm.definition = eterm.definition
    		  	 
    });
    return  $row;
}

sub merge_comments {
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
             
	   MINUS

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

