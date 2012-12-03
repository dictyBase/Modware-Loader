package Modware::Loader::Role::Ontology::WithHelper;

use namespace::autoclean;
use Moose::Role;

requires 'schema';

has '_cache' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    default => sub { [] },
    handles => {
        add_to_cache           => 'push',
        clean_cache            => 'clear',
        count_entries_in_cache => 'count',
        entries_in_cache       => 'elements'
    }
);

has '_cvrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        get_cvrow => 'get',
        set_cvrow => 'set',
        has_cvrow => 'defined'
    }
);

has '_cvterm_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { {} },
    handles => {
        get_cvterm_row => 'get',
        set_cvterm_row => 'set',
        has_cvterm_row => 'defined'
    }
);

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

sub find_or_create_dbrow {
    my ( $self, $db ) = @_;
    my $schema = $self->schema;
    my $dbrow  = $schema->resultset('General::Db')
        ->find_or_create( { name => $db } );
    $self->set_dbrow( $db, $dbrow ) if !$self->has_dbrow($db);
    return $dbrow;
}

sub find_or_create_cvrow {
    my ( $self, $cv ) = @_;
    my $schema = $self->schema;
    my $cvrow
        = $schema->resultset('Cv::Cv')->find_or_create( { name => $cv } );
    $self->set_cvrow( $cv, $cvrow )
        if !$self->has_cvrow($cv);
    return $cvrow;
}

sub find_or_create_cvterm_namespace {
    my ( $self, $cvterm, $cv, $db ) = @_;
    $cv ||= 'cvterm_property_type';
    $db ||= 'internal';
    my $schema = $self->schema;

    my $cvterm_row
        = $schema->resultset('Cv::Cvterm')->find( { name => $cvterm } );
    if ($cvterm_row) {
        $self->set_cvterm_row( $cvterm, $cvterm_row )
            if !$self->has_cvterm_row($cvterm);
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
}

sub has_idspace {
    my ( $self, $id ) = @_;
    return 1 if $id =~ /:/;
}

sub parse_id {
    my ( $self, $id ) = @_;
    return split /:/, $id;
}

sub find_or_create_db_id {
    my ( $self, $name ) = @_;
    if ( $self->has_dbrow($name) ) {
        return $self->get_dbrow($name)->db_id;
    }
    my $schema = $self->schema;
    my $row    = $schema->resultset('General::Db')
        ->find_or_create( { name => $name } );
    $self->set_dbrow( $name, $row );
    $row->db_id;
}

1;
