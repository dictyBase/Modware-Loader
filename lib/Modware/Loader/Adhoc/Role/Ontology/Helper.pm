package Modware::Loader::Adhoc::Role::Ontology::Helper;

use namespace::autoclean;
use Moose::Role;
use Carp;

requires 'chado';

has 'dbrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        add_dbrow    => 'set',
        get_dbrow    => 'get',
        delete_dbrow => 'delete',
        has_dbrow    => 'defined'
    }
);

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
    my $chado = $self->chado;
    my $row   = $chado->txn_do(
        sub {
            $chado->resultset('General::Db')
                ->find_or_create( { name => $name } );
        }
    );
    $self->add_dbrow( $name, $row );
    $row->db_id;
}

sub get_term_identifier {
    my ($self) = @_;
}

sub has_idspace {
    my ( $self, $id ) = @_;
    return 1 if $id =~ /:/;
}

sub parse_id {
    my ( $self, $id ) = @_;
    return split /:/, $id;
}

has 'cvterm_row' => (
    is        => 'rw',
    isa       => 'HashRef',
    traits    => ['Hash'],
    predicate => 'has_cvterm_row',
    default   => sub { {} },
    handles   => {
        get_cvterm_row   => 'get',
        set_cvterm_row   => 'set',
        exist_cvterm_row => 'defined'
    }
);

has 'cvrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        get_cvrow   => 'get',
        set_cvrow   => 'set',
        exist_cvrow => 'defined'
    }
);

sub _build_cvrow {
    my ($self) = @_;
    my $name   = $self->cv;
    my $cvrow  = $self->chado->resultset('Cv::Cv')
        ->find_or_create( { name => $name } );
    return { $name => $cvrow };
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

