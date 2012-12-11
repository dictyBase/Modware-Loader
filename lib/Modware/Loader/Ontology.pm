package Modware::Loader::Ontology;

use namespace::autoclean;
use Carp;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use feature qw/switch/;
use DateTime::Format::Strptime;
use Modware::Loader::Schema::Temporary;
use Module::Load::Conditional qw/check_install/;
with 'Modware::Role::WithDataStash' =>
    { create_stash_for => [qw/term relationship/] };

has 'logger' =>
    ( is => 'rw', isa => 'Log::Log4perl::Logger', writer => 'set_logger' );

has 'connect_info' => (
    is      => 'rw',
    isa     => 'Modware::Storage::Connection',
    writer  => 'set_connect_info',
    trigger => sub {
        my ($self) = @_;
        $self->_around_connection;
        $self->_register_schema_classes;
        $self->_check_cvprop_or_die;
    }
);

has 'schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    writer  => 'set_schema',
    trigger => sub {
        my ($self) = @_;
        $self->_load_engine;
    }
);

has 'ontology' => (
    is     => 'rw',
    isa    => 'OBO::Core::Ontology',
    writer => 'set_ontology'
);

has '_date_parser' => (
    is      => 'ro',
    isa     => 'DateTime::Format::Strptime',
    lazy    => 1,
    default => sub {
        return DateTime::Format::Strptime->new(
            pattern  => '%d:%m:%Y',
            on_error => 'croak'
        );
    }
);

sub _around_connection {
    my ($self)       = @_;
    my $connect_info = $self->connect_info;
    my $extra_attr   = $connect_info->extra_attribute;

    my $opt = {
        on_connect_do    => sub { $self->create_temp_statements(@_) },
        on_disconnect_do => sub { $self->drop_temp_statements(@_) }
    };
    $opt->{on_connect_call} = $extra_attr->{on_connect_do}
        if defined $extra_attr->{on_connect_do};

    $self->schema->connection( $connect_info->dsn, $connect_info->user,
        $connect_info->password, $connect_info->attribute, $opt );
    $self->schema->storage->debug( $connect_info->schema_debug );

}

sub _register_schema_classes {
    my ($self) = @_;
    my $schema = $self->schema;
    $schema->register_class(
        'TempCvterm' => 'Modware::Loader::Schema::Temporary::Cvterm' );
    $schema->register_class( 'TempCvtermRelationship' =>
            'Modware::Loader::Schema::Temporary::CvtermRelationship' );
}

sub _check_cvprop_or_die {
    my ($self) = @_;
    my $row = $self->schema->resultset('Cv::Cv')
        ->find( { name => 'cv_property' } );
    croak "cv_property ontology is not loaded\n" if !$row;
    $self->set_cvrow( 'cv_property', $row );
}

sub _load_engine {
    my ($self) = @_;
    my $schema = $self->schema;
    $self->meta->make_mutable;
    my $engine = 'Modware::Loader::Role::Ontology::Chado::With'
        . ucfirst lc( $schema->storage->sqlt_type );

    my $tmp_engine = 'Modware::Loader::Role::Ontology::Temp::With'
        . ucfirst lc( $schema->storage->sqlt_type );
    if ( !check_install( module => $tmp_engine ) ) {
        $tmp_engine = 'Modware::Loader::Role::Ontology::Temp::Generic';
    }
    ensure_all_roles( $self, ( $engine, $tmp_engine ) );
    $self->meta->make_immutable;
    $self->transform_schema;
}

sub is_ontology_in_db {
    my ($self) = @_;
    my $row = $self->schema->resultset('Cv::Cv')
        ->find( { name => $self->ontology->default_namespace } );
    if ($row) {
        $self->set_cvrow( $self->ontology->default_namespace, $row );
        return $row;
    }
}

sub is_ontology_new_version {
    my ($self) = @_;
    my $onto_datetime
        = $self->_date_parser->parse_datetime( $self->ontology->date );
    my $db_datetime = $self->_date_parser->parse_datetime(
        $self->_get_ontology_date_from_db );

    if ( $onto_datetime > $db_datetime ) {
        return $onto_datetime;
    }
}

sub _get_ontology_date_from_db {
    my ($self) = @_;
    my $cvrow;
    my $cvname = $self->ontology->default_namespace;
    if ( $self->has_cvrow($cvname) ) {
        $cvrow = $self->get_cvrow($cvname);
    }
    else {
        $cvrow
            = $self->schema->resultset('Cv::Cv')->find( { name => $cvname } );
        $self->set_cvrow( $cvname, $cvrow );
    }
    my $version_row = $cvrow->search_related(
        'cvprops',
        {   'cv.name'   => 'cv_property',
            'type.name' => 'date'
        },
        { join => [ { 'type' => 'cv' } ], rows => 1 }
    )->single;
    return $version_row->value if $version_row;
}

sub store_metadata {
    my ($self) = @_;
    my $schema = $self->schema;
    my $onto   = $self->ontology;
    my $cvrow  = $schema->resultset('Cv::Cv')
        ->find_or_new( { name => $onto->default_namespace } );
    if ( $cvrow->in_storage ) {
        my $rs = $cvrow->search_related(
            'cvprops',
            { 'cv.name' => 'cv_property' },
            { join      => [ { 'type' => 'cv' } ] }
        );
        for my $row ( $rs->all ) {
            ( my $method = $row->type->name ) =~ s{-}{_};
            if ( $method eq 'remark' ) {
                my $set = $onto->remarks;
                ( my $value ) = $set->get_set;
                next if !$value;
                $row->value($value);
            }
            else {
                $row->value( $onto->$method );
            }
            $row->update;
        }
    }
    else {
        $cvrow->insert;
        my $cvprop_id = $self->get_cvrow('cv_property')->cv_id;
        for my $method ( ( 'date', 'data_version', 'saved_by', 'remark' ) ) {
            ( my $cvterm = $method ) =~ s{_}{-};
            my $value;
            if ( $method eq 'remark' ) {
                my $set = $onto->remarks;
                ($value) = $set->get_set;
                next if !$value;
            }
            else {
                $value = $onto->$method;
            }
            $cvrow->add_to_cvprops(
                {   value   => $value,
                    type_id => $schema->resultset('Cv::Cvterm')->find(
                        {   name  => $cvterm,
                            cv_id => $cvprop_id
                        }
                    )->cvterm_id
                }
            );
        }
    }
    $self->set_cvrow( $cvrow->name, $cvrow );
}

sub find_or_create_namespaces {
    my ($self) = @_;
    $self->find_or_create_dbrow('internal');
    $self->find_or_create_cvrow($_) for qw/cvterm_property_type synonym_type/;
    $self->find_or_create_cvterm_namespace($_)
        for
        qw/comment alt_id xref cyclic reflexive transitive anonymous domain range/;
    $self->find_or_create_cvterm_namespace( $_, 'synonym_type' )
        for qw/EXACT BROAD NARROW RELATED/;

}

sub prepare_data_for_loading {
    my ($self) = @_;
    $self->load_cvterms_in_staging;
    $self->load_relationship_in_staging;
    $self->schema->storage->dbh_do(
        sub { $self->after_loading_in_staging(@_) } );

}

sub entries_in_staging {
    my ( $self, $name ) = @_;
    return $self->schema->resultset($name)->count( {} );
}

sub merge_ontology {
    my ($self)  = @_;
    my $storage = $self->schema->storage;
    my $logger  = $self->logger;

    #remove terms that are pruned(present in database but not in file)
    my $deleted_terms
        = $storage->dbh_do( sub { $self->delete_non_existing_terms(@_) } );
    $logger->info("deleted $deleted_terms terms");

    #This has to be run first in order to get the list of existing cvterms
    #particularly before the staging and live tables get synced
    my $updated_terms = $storage->dbh_do( sub { $self->update_cvterms(@_) } );
    $logger->info("updated $updated_terms cvterms");
    my $cvterm_names
        = $storage->dbh_do( sub { $self->update_cvterm_names(@_) } );
    $logger->info("updated $cvterm_names cvterm names");

    #create new terms both in dbxref and cvterm tables
    my $dbxrefs = $storage->dbh_do( sub { $self->create_dbxrefs(@_) } );
    $logger->info("created $dbxrefs dbxrefs");
    if ($dbxrefs) {
        my $cvterms
            = $storage->dbh_do( sub { $self->create_cvterms(@_) } );
        $logger->info("created $cvterms cvterms");
    }

    #create relationships
    my $relationships
        = $storage->dbh_do( sub { $self->create_relations(@_) } );
    $logger->info("created $relationships relationships");

}

with 'Modware::Loader::Role::Ontology::WithHelper';
__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

