package Modware::Loader::Adhoc::Role::Ontology::Helper;

use namespace::autoclean;
use Moose::Role;
use Carp;

requires 'chado';

has '_dbrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_dbrow    => 'set',
        get_dbrow    => 'get',
        delete_dbrow => 'delete',
        has_dbrow    => 'defined'
    }
);

has 'cvterm_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        get_cvterm_row   => 'get',
        set_cvterm_row   => 'set',
        exist_cvterm_row => 'defined',
        has_cvterm_row   => 'defined'
    }
);

has '_cvrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        get_cvrow   => 'get',
        set_cvrow   => 'set',
        has_cvrow   => 'defined',
        exist_cvrow => 'defined'
    }
);

sub find_or_create_dbrow {
    my ( $self, $db ) = @_;
    if ( $self->has_dbrow($db) ) {
        return $self->get_dbrow($db);
    }
    my $dbrow = $self->chado->resultset('General::Db')
        ->find_or_create( { name => $db } );
    $self->set_dbrow( $db, $dbrow );
    return $dbrow;
}

sub find_or_create_cvrow {
    my ( $self, $cv ) = @_;
    if ( $self->has_cvrow($cv) ) {
        return $self->get_cvrow($cv);
    }
    my $cvrow = $self->chado->resultset('Cv::Cv')
        ->find_or_create( { name => $cv } );
    $self->set_cvrow( $cv, $cvrow );
    return $cvrow;
}

sub find_or_create_cvterm_namespace {
    my ( $self, $cvterm, $cv, $db ) = @_;
    $cv ||= 'cvterm_property_type';
    $db ||= 'internal';
    my $schema = $self->chado;

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
                db_id     => $self->get_dbrow($db)->db_id
            }
            );
        $cvterm_row = $schema->resultset('Cv::Cvterm')->create(
            {   name      => $cvterm,
                cv_id     => $self->get_cvrow($cv)->cv_id,
                dbxref_id => $dbxref_row->dbxref_id
            }
        );
        $self->set_cvterm_row( $cvterm, $cvterm_row );
    }
    return $cvterm_row;
}

sub find_cvterm_by_id {
    my ( $self, $identifier, $cv ) = @_;
    my $row;
    if ( $self->has_idspace($identifier) ) {
        my ( $db, $id ) = $self->parse_id($identifier);
        $row = $self->chado->resultset('Cv::Cvterm')->search(
            {   'dbxref.accession' => $id,
                'cv.name'          => $cv,
                'db.name'          => $db
            },
            { join => [ 'cv', { 'dbxref' => 'db' } ], rows => 1 }
        )->single;
        return $row if $row;
    }

    $row
        = $self->chado->resultset('Cv::Cvterm')
        ->search( { 'dbxref.accession' => $identifier, 'cv.name' => $cv },
        { join => [qw/cv dbxref/], rows => 1 } )->single;

    return $row if $row;

}

sub find_or_create_db_id {
    my ( $self, $name ) = @_;
    if ( $self->has_dbrow($name) ) {
        return $self->get_dbrow($name)->db_id;
    }
    my $row = $self->chado->resultset('General::Db')
        ->find_or_create( { name => $name } );
    $self->set_dbrow( $name, $row );
    $row->db_id;
}

sub find_relation_term {
    my ( $self, $cvterm, $cv ) = @_;

    ## -- extremely redundant call have to cache later ontology
    my $rs = $self->chado->resultset('Cv::Cvterm')->search(
        {   'me.name' => $cvterm,
            'cv.name' => $cv
        },
        { join => 'cv' }
    );

    if ( $rs->count ) {
        return $rs->first;
    }
}

sub has_idspace {
    my ( $self, $id ) = @_;
    return 1 if $id =~ /:/;
}

sub parse_id {
    my ( $self, $id ) = @_;
    return split( /:/, $id, 2 );
}

sub find_dbxref_id {
    my ( $self, $dbxref, $db ) = @_;
    my $rs = $self->chado->resultset('General::Dbxref')->search(
        {   accession => $dbxref,
            db_id     => $db
        }
    );
    if ( $rs->count ) {
        return $rs->first->dbxref_id;
    }
}

sub find_dbxref_id_by_cvterm {
    my ( $self, $dbxref, $db, $cv, $cvterm ) = @_;
    my $rs = $self->chado->resultset('General::Dbxref')->search(
        {   'accession'   => $dbxref,
            'db.name'     => $db,
            'cvterm.name' => $cvterm,
            'cv.name'     => $cv
        },
        { join => [ 'db', { 'cvterm' => 'cv' } ] }
    );
    if ( $rs->count ) {
        return $rs->first->dbxref_id;
    }
}

sub find_relation {
    my ( $self, $subject, $object, $predicate ) = @_;
    return $self->chado->resultset('Cv::CvtermRelationship')->search(
        {   subject_id => $subject->cvterm_id,
            object_id  => $object->cvterm_id,
            type_id    => $predicate->cvterm_id
        },
        { rows => 1 }
    )->single;
}

sub find_cvterm_id_by_term_id {
    my ( $self, $cvterm, $cv ) = @_;

    if ( $self->do_parse_id and $self->has_idspace($cvterm) ) {
        my ( $db, $id ) = $self->parse_id($cvterm);
        my $rs = $self->chado->resultset('Cv::Cvterm')->search(
            {   'dbxref.accession' => $id,
                'cv.name'          => $cv,
                'db.name'          => $db
            },
            { join => [ 'cv', { 'dbxref' => 'db' } ] }
        );

        if ( $rs->count ) {
            return $rs->first->cvterm_id;
        }
    }

    my $rs
        = $self->chado->resultset('Cv::Cvterm')
        ->search( { 'dbxref.accession' => $cvterm, 'cv.name' => $cv },
        { join => [qw/cv dbxref/] } );

    if ( $rs->count ) {
        return $rs->first->cvterm_id;
    }
}

sub find_or_create_cvterm_id {
    my ( $self, $cvterm, $cv, $db, $dbxref ) = @_;

    $dbxref ||= $cv . '-' . $db . '-' . $cvterm;

    if ( $self->exist_cvterm_row($cvterm) ) {
        my $row = $self->get_cvterm_row($cvterm);
        return $row->cvterm_id if $row->cv->name eq $cv;
    }

    #otherwise try to retrieve from database
    my $rs
        = $self->chado->resultset('Cv::Cvterm')
        ->search( { 'me.name' => $cvterm, 'cv.name' => $cv },
        { join => 'cv' } );
    if ( $rs->count > 0 ) {
        $self->set_cvterm_row( $cvterm => $rs->first );
        return $rs->first->cvterm_id;
    }

    #otherwise create one using the default cv namespace
    my $row = $self->chado->resultset('Cv::Cvterm')->create_with(
        {   name   => $cvterm,
            cv     => $cv,
            db     => $db,
            dbxref => $dbxref
        }
    );
    $self->set_cvterm_row( $cvterm, $row );
    $row->cvterm_id;
}

sub find_cvterm_id {
    my ( $self, $cvterm, $cv ) = @_;

    if ( $self->exist_cvterm_row($cvterm) ) {
        my $row = $self->get_cvterm_row($cvterm);
        return $row->cvterm_id if $row->cv->name eq $cv;
    }

    #otherwise try to retrieve from database
    my $rs
        = $self->chado->resultset('Cv::Cvterm')
        ->search( { 'me.name' => $cvterm, 'cv.name' => $cv },
        { join => 'cv' } );
    if ( $rs->count > 0 ) {
        $self->set_cvterm_row( $cvterm => $rs->first );
        return $rs->first->cvterm_id;
    }

    #croak "no cvterm id found for $cvterm\n";
}

sub cvterm_id_by_name {
    my ( $self, $name ) = @_;

    #check if it is already been cached
    if ( $self->exist_cvterm_row($name) ) {
        return $self->get_cvterm_row($name)->cvterm_id;
    }

    #otherwise try to retrieve from database
    my $rs
        = $self->chado->resultset('Cv::Cvterm')->search( { name => $name } );
    if ( $rs->count > 0 ) {
        $self->set_cvterm_row( $name => $rs->first );
        return $rs->first->cvterm_id;
    }

    #otherwise create one using the default cv namespace
    my $row = $self->chado->resultset('Cv::Cvterm')->create_with(
        {   name   => $name,
            cv     => $self->cv,
            db     => $self->db,
            dbxref => $self->cv . '-' . $self->db . '-' . $name
        }
    );
    $self->set_cvterm_row( $name, $row );
    $row->cvterm_id;
}

sub cvterm_ids_by_namespace {
    my ( $self, $name ) = @_;

    if ( $self->exist_cvrow($name) ) {
        my $ids = [ map { $_->cvterm_id } $self->get_cvrow($name)->cvterms ];
        return $ids;
    }

    my $rs = $self->chado->resultset('Cv::Cv')->search( { name => $name } );
    if ( $rs->count > 0 ) {
        my $row = $rs->first;
        $self->set_cvrow( $name, $row );
        my $ids = [ map { $_->cvterm_id } $row->cvterms ];
        return $ids;
    }
    croak "the given cv namespace $name does not exist : create one\n";
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

