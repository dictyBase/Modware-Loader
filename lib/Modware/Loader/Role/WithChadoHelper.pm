package Modware::Loader::Role::WithChadoHelper;

use namespace::autoclean;
use Moose::Role;
with 'Modware::Role::WithDataStash' =>
    { create_kv_stash_for => [qw/cv cvterm db dbxref/] };

requires 'schema';

sub get_organism_row {
    my ( $self, $organism ) = @_;
    my $row
        = $self->schema->resultset('Organism::Organism')
        ->find(
        { species => $organism->species, genus => $organism->genus } );
    return $row if $row;
}

sub find_or_create_cvterm_row {
    my ( $self, $options ) = @_;
    if ( my $row
        = $self->find_cvterm_row( $options->{cvterm}, $options->{cv} ) )
    {
        return $row;
    }
    my $key    = $options->{cv} . '-' . $options->{cvterm};
    my $dbxref = $self->find_or_create_dbxref_row( $options->{dbxref},
        $options->{db} );
    my $cvterm_row = $self->schema->resultset('Cv::Cvterm')->create(
        {   name      => $options->{cvterm},
            cv_id     => $self->find_or_create_cvrow( $options->{cv} )->cv_id,
            dbxref_id => $dbxref->dbxref_id
        }
    );
    $self->set_cvterm_row( $key, $cvterm_row );
    return $cvterm_row;
}

sub find_cvterm_row {
    my ( $self, $cvterm, $cv ) = @_;
    my $key = $cv . '-' . $cvterm;
    if ( $self->has_cvterm_row($key) ) {
        return $self->get_cvterm_row($key);
    }
    my $row = $self->schema->resultset('Cv::Cvterm')
        ->find( { 'cv.name' => $cv, 'name' => $cvterm }, { join => 'cv' } );
    if ($row) {
        $self->set_cvterm_row( $key, $row );
        return $row;
    }
}

sub find_or_create_dbxref_row {
    my ( $self, $dbxref, $db ) = @_;
    if ( $self->has_dbxref_row($dbxref) ) {
        return $self->get_dbxref_row($dbxref);
    }
    my $row = $self->schema->resultset('General::Dbxref')->find(
        {   'accession' => $dbxref,
            'db.name'   => $db
        },
        { join => 'db' }
    );

    if ($row) {
        $self->set_dbxref_row( $dbxref, $row );
    }
    else {
        $row = $self->schema->resultset('General::Dbxref')
            ->create( { accession => $dbxref, db => { name => $db } } );
        $self->set_dbxref_row( $dbxref, $row );
    }
    return $row;
}

sub find_or_create_dbrow {
    my ( $self, $db ) = @_;
    if ( $self->has_dbrow($db) ) {
        return $self->get_dbrow($db);
    }
    my $dbrow = $self->schema->resultset('General::Db')
        ->find_or_create( { name => $db } );
    $self->set_dbrow( $db, $dbrow );
    return $dbrow;
}

sub find_or_create_cvrow {
    my ( $self, $cv ) = @_;
    if ( $self->has_cvrow($cv) ) {
        return $self->get_cvrow($cv);
    }
    my $cvrow = $self->schema->resultset('Cv::Cv')
        ->find_or_create( { name => $cv } );
    $self->set_cvrow( $cv, $cvrow );
    return $cvrow;
}

sub find_or_create_cvterm_namespace {
    my ( $self, $cvterm, $cv, $db ) = @_;
    $cv ||= 'cvterm_property_type';
    $db ||= 'internal';
    my $schema = $self->schema;

    if ( $self->has_cvterm_row($cvterm) ) {
        return $self->get_cvterm_row($cvterm);
    }
    my $cvterm_row = $schema->resultset('Cv::Cvterm')
        ->find( { name => $cvterm, 'cv.name' => $cv }, { join => 'cv' } );
    if ($cvterm_row) {
        $self->set_cvterm_row( $cvterm, $cvterm_row );
    }
    else {
        my $dbxref_row
            = $schema->resultset('General::Dbxref')->find_or_create(
            {   accession => $cvterm,
                db_id     => $self->find_or_create_dbrow($db)->db_id
            }
            );
        $cvterm_row = $schema->resultset('Cv::Cvterm')->create(
            {   name      => $cvterm,
                cv_id     => $self->find_or_create_cvrow($cv)->cv_id,
                dbxref_id => $dbxref_row->dbxref_id
            }
        );
        $self->set_cvterm_row( $cvterm, $cvterm_row );
    }
    return $cvterm_row;
}

sub normalize_id {
    my ( $self, $id, $db ) = @_;
    my ( $db_id, $accession );
    if ( $self->has_idspace($id) ) {
        my @parsed = $self->parse_id($id);
        $db_id     = $self->find_or_create_dbrow( $parsed[0] )->db_id;
        $accession = $parsed[1];
    }
    else {
        $db ||= 'internal';
        $db_id     = $self->find_or_create_dbrow($db)->db_id;
        $accession = $id;
    }
    return ( $db_id, $accession );
}

sub has_idspace {
    my ( $self, $id ) = @_;
    return 1 if $id =~ /:/;
}

sub parse_id {
    my ( $self, $id ) = @_;
    return split /:/, $id;
}

1;

