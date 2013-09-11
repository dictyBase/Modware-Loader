package Modware::Loader::Role::Ontology::Chado::WithSqlite;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use feature qw/say/;

# Module implementation
#

sub transform_schema { }

sub delete_non_existing_terms {
    my ( $self, $storage, $dbh ) = @_;
    my $data
        = $dbh->selectall_arrayref(
        $self->sqllib->retr('select_non_existing_cvterm'),
        { Slice => {} } );

    my $schema = $self->schema;
    for my $row (@$data) {
        $schema->resultset('Cv::Cvterm')->find( $row->{cvterm_id} )->delete;
        $schema->resultset('General::Dbxref')->find( $row->{dbxref_id} )
            ->delete;
    }
    return scalar @$data;
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

#SQLite do not support JOINS in update statements,  so it's need to be done in few
#more steps
#This will update the name of cvterms.
    my $data
        = $dbh->selectall_arrayref(
        $self->sqllib->retr('select_fresh_cvterm'),
        { Slice => {} } );
    for my $frow (@$data) {
        my $dbrow
            = $self->schema->resultset('Cv::Cvterm')
            ->find( $frow->{cvterm_id} )
            ->update( { name => $frow->{fname} } );
    }
    return scalar @$data;
}

sub update_cvterms {
    my ( $self, $storage, $dbh ) = @_;

    $dbh->do( $self->sqllib->retr('insert_existing_accession') );

# This will update definition and status of all cvterms, as usual it is more work in case
# of SQLite existing cvterms
    my $data
        = $dbh->selectall_arrayref(
        $self->sqllib->retr('select_existing_cvterm'),
        { Slice => {} } );
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

sub create_relations {
    my ( $self, $storage, $dbh ) = @_;
    my $rows = $dbh->do( $self->sqllib->retr('insert_relationship') );
    return $rows;
}

sub create_synonyms {
    my ( $self, $storage, $dbh ) = @_;

    # Identical to comment creation logic
    my $row = $dbh->do( $self->sqllib->retr('insert_synonym') );
    $self->logger->debug("created $row synonyms");
    return $row;
}

sub update_synonyms {
    my ( $self, $storage, $dbh ) = @_;

    my $sqllib = $self->sqllib;

    #First create a temp table with synonym that needs update
    #$dbh->do( $sqllib->retr('insert_updated_synonym_in_temp') );

    #Now delete existing synonyms
    $dbh->do( $sqllib->retr('delete_updatable_synonym') );

    #Now insert the new batch
    my $rows = $dbh->do( $sqllib->retr('insert_updatable_synonym') );
    $self->logger->debug("updated $rows synonyms");
    return $rows;
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Loader::Role::Chado::BCS::Engine::Oracle

