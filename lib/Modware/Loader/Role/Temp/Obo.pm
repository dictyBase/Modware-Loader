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
    $self->inject_tmp_schema;
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

sub load_all_in_temp {
    my ($self) = @_;
    my $schema = $self->chado;
    my $guard  = $schema->txn_scope_guard;

    $self->load_cvterm_in_temp;
    $self->load_relation_in_temp;
    $self->load_relation_attr_in_temp;
    $self->load_synonym_in_temp;
    $self->load_alt_ids_in_temp;
    $self->load_xref_in_tmp;

    $guard->commit;
}

sub load_cvterm_in_tmp {
    my ($self) = @_;
    my $logger = $self->logger;
    my $schema = $self->chado;

    $logger->log( "going to load " $self->node_count,
        " cvterms in temp table" );
    $self->add_node_header(
        [   qw/name db_id cv_id accession definition is_obsolete is_relationshiptype
                cmmt/
        ]
    );
    $schema->resultset('TempCvAll')->populate( [ $self->get_all_nodes ] );
    my $count = $schema->resultset('TempCvAll')
        ->count( {}, { select => 'accession' } );
    $logger->log("loaded $count cvterms in temp table");

}

sub load_relation_in_tmp {
    my ($self) = @_;
    my $logger = $self->logger;
    my $schema = $self->chado;

    $logger->log( "going to load " $self->relation_count,
        " relations in temp table" );

    my $relations = [ $self->all_relations ];
    unshift @$relations, [qw/subject object predicate/];
    $schema->resultset('TempRelation')->populate($relations);
    my $count = $schema->resultset('TempRelation')
        ->count( {}, { select => 'subject' } );

    $logger->log("loaded $count relations in temp table");
}

sub load_relation_attr_in_tmp {
    my ($self) = @_;
    my $logger = $self->logger;
    my $schema = $self->chado;

    $logger->log(
        "going to load " $self->relation_attr_count,
        " relation attributes in temp table"
    );

    $self->add_relation_attr_header(
        [qw/name relation_value relation_attr/] );
    $schema->resultset('TempRelationAttr')
        ->populate( [ $self->all_rel_attrs ] );
    my $count = $schema->resultset('TempRelationAttr')
        ->count( {}, { select => 'relation_attr' } );
    $logger->log("loaded $count relation attributes in temp table");
}

sub load_synonym_in_tmp {
    my ($self) = @_;
    my $logger = $self->logger;
    my $schema = $self->chado;

    $logger->log(
        "going to load " $self->synonym_count,
        " synonyms in temp table"
    );

    $self->add_synonym_header(
        [qw/type_id name syn is_obsolete/] );
    $schema->resultset('TempSyn')
        ->populate( [ $self->all_synonyms ] );
    my $count = $schema->resultset('TempSyn')
        ->count( {}, { select => 'syn' } );
    $logger->log("loaded $count synonyms in temp table");
}

sub load_alt_ids_in_tmp {
    my ($self) = @_;
    my $logger = $self->logger;
    my $schema = $self->chado;

    $logger->log(
        "going to load " $self->alt_ids_count,
        " alt ids in temp table"
    );

    $self->add_alt_id_header(
        [qw/accession name db_id/] );
    $schema->resultset('TempAltId')
        ->populate( [ $self->all_alt_ids ] );
    my $count = $schema->resultset('TempAltId')
        ->count( {}, { select => 'accession' } );

    $logger->log("loaded $count alt ids in temp table");
}

sub load_xref_in_tmp {
    my ($self) = @_;
    my $logger = $self->logger;
    my $schema = $self->chado;

    $logger->log(
        "going to load " $self->xref_count,
        " xrefs in temp table"
    );

    $self->add_xref_header(
        [qw/accession name db_id is_obsolete/] );
    $schema->resultset('TempXref')
        ->populate( [ $self->all_xrefs] );
    my $count = $schema->resultset('TempXref')
        ->count( {}, { select => 'accession' } );

    $logger->log("loaded $count xrefs temp table");
}
1;    # Magic true value required at end of module

