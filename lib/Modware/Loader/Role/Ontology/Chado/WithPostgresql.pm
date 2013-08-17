package Modware::Loader::Role::Ontology::Chado::WithPostgresql;

# Other modules:
use namespace::autoclean;
use Moose::Role;

# Module implementation
#

sub transform_schema { }

sub delete_non_existing_terms {
    my ( $self, $storage, $dbh ) = @_;
    my $sqllib = $self->sqllib;
    $dbh->do( $sqllib->retr('insert_temp_term_delete') );
    $dbh->do( $sqllib->retr('delete_non_existing_cvterm') );
    my $rows = $dbh->do( $sqllib->retr('delete_non_existing_dbxref') );
    return $rows;
}

sub create_dbxrefs {
    my ( $self, $storage, $dbh ) = @_;
    $dbh->do( $self->sqllib->retr('insert_new_accession') );

    my $rows = $dbh->do( $self->sqllib->retr('insert_dbxref') );
    return $rows;
}

sub create_cvterms {
    my ( $self, $storage, $dbh ) = @_;
    my $rows = $dbh->do( $self->sqllib->retr('insert_cvterm') );
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
    my $row = $dbh->do( $self->sqllib->retr('update_cvterm_names') );
    return $row;
}

sub update_cvterms {
    my ( $self, $storage, $dbh ) = @_;
    $dbh->do( $self->sqllib->retr('insert_existing_accession') );
    my $row = $dbh->do( $self->sqllib->retr('update_cvterms') );
    return $row;
}

sub create_relations {
    my ( $self, $storage, $dbh ) = @_;
    my $rows = $dbh->do( $self->sqllib->retr('insert_relationship') );
    return $rows;
}

sub create_synonyms {
    my ( $self, $storage, $dbh ) = @_;

    # The logic here is as follows
    #  Get the list of new synonyms for new dbxrefs(from temp_accession table)
    #  Join across cvterm table to get their cvterm_id
    #  Join with db table to make sure the dbxref belong to correct namespace
    my $row = $dbh->do( $self->sqllib->retr('insert_synonym') );
    $self->logger->debug("created $row synonyms");
    return $row;
}

sub update_synonyms {
    my ( $self, $storage, $dbh ) = @_;

    my $sqllib = $self->sqllib;

    #First create a temp table with synonym that needs update
    $dbh->do( $sqllib->retr('insert_updated_synonym_in_temp') );

    #Delete all existing synonyms that needs update
    $dbh->do($sqllib->retr('delete_updatable_synonym'));

    #Now insert the new batch
    my $rows = $dbh->do( $self->sqllib->retr('insert_updatable_synonym) );
    $self->logger->debug("updated $rows synonyms");
    return $rows;
}

sub create_comments {
    my ( $self, $storage, $dbh ) = @_;

# The logic here to get a list of new cvterms and their comments.
# A temp table(temp_accession) with all the new cvterms were created which is turn joined
# with cvterm table to get their cvterm_id
    my $row = $dbh->do( $self->sqllib->retr('insert_comment') );
    $self->logger->debug("created $row comment");
    return $row;
}

sub update_comments {
    my ( $self, $storage, $dbh ) = @_;

    #DELETE existing comment
        $dbh->do( $self->sqllib->retr('delete_updatable_comment') );

    #INSERT all comments from temp table
    my $rows = $dbh->do( $self->sqllib->retr('insert_updatable_comment') );
    $self->logger->debug("updated $rows comment");
    return $rows;
}


1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Loader::Role::Chado::BCS::Engine::Oracle

