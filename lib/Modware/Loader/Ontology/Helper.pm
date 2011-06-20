package Modware::Loader::Ontology::Helper;

use namespace::autoclean;
use Moose;
use MooseX::Params::Validate;
use Modware::Types qw/Schema/;
with 'Modware::Role::Chado::Helper::BCS::Cvterm';

has 'runner' => (
    is      => 'rw',
    isa     => 'MooseX::App::Cmd::Command',
    handles => [qw/chado do_parse_id/]
);

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
    my ( $self, $dbxref, $db ) = validated_list(
        \@_,
        dbxref => { isa => 'Str' },
        db     => { isa => 'Str' },
    );

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
    my ( $self, $dbxref, $db, $cv, $cvterm ) = validated_list(
        \@_,
        dbxref => { isa => 'Str' },
        db     => { isa => 'Str' },
        cv     => { isa => 'Str' },
        cvterm => { isa => 'Str' },
    );

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

sub find_relation_term_id {
    my ( $self, $cvterm, $cv ) = validated_list(
        \@_,
        cvterm => { isa => 'Str' },
        cv     => { isa => 'ArrayRef' }
    );

    ## -- extremely redundant call have to cache later ontology
    my $rs = $self->chado->resultset('Cv::Cvterm')->search(
        {   'me.name' => $cvterm,
            'cv.name' => { -in => $cv }
        },
        { join => 'cv' }
    );

    if ( $rs->count ) {
        return $rs->first->cvterm_id;
    }
}

sub find_cvterm_id_by_term_id {
    my ( $self, $cvterm, $cv ) = validated_list(
        \@_,
        term_id => { isa => 'Str' },
        cv      => { isa => 'Str' },
    );

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

sub has_idspace {
    my ( $self, $id ) = @_;
    return 1 if $id =~ /:/;
}

sub parse_id {
    my ( $self, $id ) = @_;
    return split /:/, $id;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

