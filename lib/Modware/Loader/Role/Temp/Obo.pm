package Modware::Loader::Role::Temp::Obo;

# Other modules:
use strict;
use namespace::autoclean;
use Moose::Role;
use Moose::Util qw/ensure_all_roles/;
use Class::MOP;
use DBI;
use Modware::Loader::Schema::Result::Temp::Obo;

# Module implementation
#

after 'dsn' => sub {
    my ( $self, $value ) = @_;
    return if !$value;
    my ( $schema, $driver ) = DBI->parse_dsn($value);
    $driver = ucfirst( lc $driver );

    $self->meta->make_mutable;
    ensure_all_roles( $self, 'Modware::Loader::Role::Temp::Obo::' . $driver );
    $self->meta->make_immutable;

    $self->add_on_connect( $self->on_connect_sql )
        for $self->has_on_connect_sql;
    $self->add_on_disconnect( $self->on_disconnect_sql )
        for $self->has_on_disconnect_sql;
};

sub inject_tmp_schema {
    my $self = shift;
    Class::MOP::load_class('Modware::Loader::Schema::Result::Temp::Obo');
    $self->chado->register_class(
        'TempCvAll' => 'Modware::Loader::Schema::Result::Temp::Ont::Core' );
    $self->chado->register_class(
        'TempCvNew' => 'Modware::Loader::Schema::Result::Temp::Ont::New' );
    $self->chado->register_class( 'TempCvExist' =>
            'Modware::Loader::Schema::Result::Temp::Ont::Exist' );
    $self->chado->register_class( 'TempRelation' =>
            'Modware::Loader::Schema::Result::Temp::Ont::Relation' );
    $self->chado->register_class(
        'TempSyn' => 'Modware::Loader::Schema::Result::Temp::Ont::Syn' );
    $self->chado->register_class(
        'TempAltId' => 'Modware::Loader::Schema::Result::Temp::Ont::AltId' );
    $self->chado->register_class(
        'TempXref' => 'Modware::Loader::Schema::Result::Temp::Ont::Xref' );
    $self->chado->register_class( 'TempRelationAttr' =>
            'Modware::Loader::Schema::Result::Temp::Ont::Relation' );
}

sub load_data {
}

1;    # Magic true value required at end of module

