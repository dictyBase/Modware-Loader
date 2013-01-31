
use strict;

package Modware::Loader::Role::GAF::DbxrefId;

use Moose::Role;

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

has '_dbxref_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_dbxref_row    => 'set',
        get_dbxref_row    => 'get',
        delete_dbxref_row => 'delete',
        has_dbxref_row    => 'defined'
    }
);

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

sub find_or_create_dbxref_id {
    my ( $self, $dbxref ) = @_;
    my @db_vals = split( /:/, $dbxref );

    if ( $self->has_dbxref_row( $db_vals[1] ) ) {
        return $self->get_dbxref_row( $db_vals[1] )->dbxref_id;
    }
    my $row = $self->schema->resultset('General::Dbxref')->search(
        { accession => $db_vals[1] },
        { select [qw/dbxref_id accession/] }
    );
    if ( $row->count > 0 ) {
        $self->set_dbxref_row( $db_vals[1], $row->first );
        return $self->get_dbxref_row( $db_vals[1] )->dbxref_id;
    }
    else {
        my $new_dbxref_row = $schema->resultset('General::Dbxref')->create(
            {   accession => $db_vals[1],
                db_id     => $self->find_or_create_db_id( $db_vals[0] )
            }
        );
        $self->set_dbxref_row( $db_vals[1], $new_dbxref_row );
        return $self->get_dbxref_row( $db_vals[1] )->dbxref_id;
    }
}

has '_features' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => {
        set_feature_id => 'set',
        get_feature_id => 'get',
        has_feature    => 'defined'
    },
    builder => '_populate_features',
    lazy    => 1
);

sub _populate_features {
    my ($self) = @_;
    my $stack;
    my $rs = $self->schema->resultset('Sequence::Feature')->search(
        { 'type.name' => 'gene' },
        {   join   => [qw/dbxref type/],
            select => [qw/dbxref.accession feature_id/]
        }
    );
    $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    while ( my $ref = $rs->next ) {
        $stack->{ $ref->{dbxref}->{accession} } = $ref->{feature_id};
    }
    return $stack;
}

has '_cvterms' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => {
        set_cvterm_id => 'set',
        get_cvterm_id => 'get',
        has_cvterm    => 'defined'
    },
    builder => '_populate_cvterms',
    lazy    => 1
);

sub _populate_cvterms {
    my ($self) = @_;
    my $stack;
    my $rs = $self->schema->resultset('Cv::Cvterm')->search(
        { 'db.name' => 'GO' },
        {   join   => { dbxref => 'db' },
            select => [qw/db.name dbxref.accession cvterm_id/]
        }
    );
    $rs->result_class('DBIx::Class::ResultClass::HashRefInflator');
    while ( my $ref = $rs->next ) {
        $stack->{ $ref->{db}->{name} . ":" . $ref->{dbxref}->{accession} }
            = $ref->{cvterm_id};
    }
    return $stack;
}

has 'ev_codes' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_cvterm_id_for_ev => 'set',
        get_cvterm_id_for_ev => 'get',
        has_cvterm_for_ev    => 'defined'
    }
);

sub find_cvterm_id_for_evidence_code {
    my ( $self, $ev ) = @_;
    if ( $self->has_cvterm_for_ev($ev) ) {
        return $self->get_cvterm_id_for_ev($ev);
    }
    my $row
        = $self->schema->resultset('Cv::Cv')
        ->search( { 'name' => { -like => 'evidence_code%' } } )
        ->first->cvterms->search_related(
        'cvtermsynonyms',
        {   'type.name' => { -in => [qw/EXACT RELATED BROAD/] },
            'cv.name'   => 'synonym_type',
            'synonym_'  => $ev
        },
        {   join   => { type => 'cv' },
            cache  => 1,
            select => 'cvterm_id'
        }
        );
    if ( $row->count > 0 ) {
        $self->set_cvterm_id_for_ev( $ev, $row->first->cvterm_id );
        return $row->first->cvterm_id;
    }
}

has 'publications' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_pub_id => 'set',
        get_pub_id => 'get',
        has_pub    => 'defined'
    }
);

sub find_pub_id {
    my ( $self, $dbref ) = @_;
    $dbref =~ s/^[A-Z_]{4,9}://x;
    if ( $self->has_pub($dbref) ) {
        $self->get_pub_id($dbref);
    }
    my $row = $self->schema->resultset('Pub::Pub')
        ->search( { uniquename => $dbref }, { select => 'pub_id' } );
    if ( $row->count > 0 ) {
        $self->set_pub_id( $dbref, $row->first->pub_id );
        return $row->first->pub_id;
    }
    else {
        $self->logger->warn( 'Column 6 ID - ' . $dbref . ' DOES NOT exist' );
        return undef;
    }
}

1;

