package Modware::Loader::Ontology;

use namespace::autoclean;
use Carp;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use feature qw/switch/;
use DateTime::Format::Strptime;
use Modware::Loader::Schema::Temporary;
use DBI;
use Encode;
use utf8;
use Data::Dumper;
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
    my $engine = 'Modware::Loader::Role::Ontology::With'
        . ucfirst lc( $schema->storage->sqlt_type );
    ensure_all_roles( $self, $engine );
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
    $self->load_relationship_in_stating;
}

sub load_cvterms_in_staging {
    my ($self)        = @_;
    my $onto          = $self->ontology;
    my $schema        = $self->schema;
    my $default_cv_id = $self->get_cvrow( $onto->default_namespace )->cv_id;

    #Term
    for my $term ( @{ $onto->get_relationship_types, $onto->get_terms } ) {
        my $insert_hash = $self->_get_insert_term_hash($term);
        $insert_hash->{cv_id}
            = $term->namespace
            ? $self->find_or_create_cvrow( $term->namespace )->cv_id
            : $default_cv_id;
        $self->add_to_term_cache($insert_hash);
        if ( $self->count_entries_in_term_cache >= $self->cache_threshold ) {
            $schema->resultset('TempCvterm')
                ->populate( [ $self->entries_in_term_cache ] );
            $self->clean_term_cache;
        }
    }

    if ( $self->count_entries_in_term_cache ) {
        $schema->resultset('TempCvterm')
            ->populate( [ $self->entries_in_term_cache ] );
        $self->clean_term_cache;
    }
}

sub load_relationship_in_stating {
    my ($self) = @_;
    my $onto   = $self->ontology;
    my $schema = $self->schema;

    for my $rel ( @{ $onto->get_relationships } ) {
        $self->add_to_relationship_cache(
            {   object  => $rel->head->name,
                subject => $rel->tail->name,
                type    => $rel->type
            }
        );
        if ( $self->count_entries_in_relationship_cache
            >= $self->cache_threshold )
        {
            $schema->resultset('TempCvtermRelationship')
                ->populate( [ $self->entries_in_relationship_cache ] );
            $self->clean_relationship_cache;
        }
    }
    if ( $self->count_entries_in_relationship_cache ) {
        $schema->resultset('TempCvtermRelationship')
            ->populate( [ $self->entries_in_relationship_cache ] );
        $self->clean_relationship_cache;
    }
}

sub entries_in_staging {
    my ( $self, $name ) = @_;
    return $self->schema->resultset($name)->count( {} );
}

sub _get_insert_term_hash {
    my ( $self, $term ) = @_;
    my ( $db_id, $accession );
    if ( $self->has_idspace( $term->id ) ) {
        my @parsed = $self->parse_id( $term->id );
        $db_id     = $self->find_or_create_db_id( $parsed[0] );
        $accession = $parsed[1];
    }
    else {
        $db_id     = $self->find_or_create_db_id( $self->cv_namespace->name );
        $accession = $term->id;
    }

    my $insert_hash;
    $insert_hash->{accession} = $accession;
    $insert_hash->{db_id}     = $db_id;
    if ( my $text = $term->def->text ) {
        $insert_hash->{definition} = encode( "UTF-8", $text );
    }
    $insert_hash->{is_relationshiptype}
        = $term->isa('OBO::Core::RelationshipType') ? 1 : 0;
    $insert_hash->{is_obsolete} = $term->is_obsolete ? 1 : 0;
    $insert_hash->{name} = $term->name ? $term->name : $term->id;
    $insert_hash->{comment} = $term->comment;
    return $insert_hash;
}

sub merge_ontology {
    my ($self)  = @_;
    my $storage = $self->schema->storage;
    my $logger  = $self->logger;

    my $dbxrefs = $storage->dbh_do( sub { $self->create_dbxrefs(@_) } );
    $logger->info("created $dbxrefs dbxrefs");

    if ($dbxrefs) {
        my $cvterms = $storage->dbh_do( sub { $self->create_cvterms(@_) } );
        $logger->info("created $cvterms cvterms");
    }
    my $cvterm_names = $storage->dbh_do(sub {$self->update_cvterm_names(@_)});
    $logger->info("updated $cvterms_names cvterm names");

    my $update_terms = $storage->dbh_do(sub {$self->update_cvterms(@_)});
    $logger->info("updated $updated_terms cvterms");

    my $relationships
        = $storage->dbh_do( sub { $self->create_relations(@_) } );
        $logger->info("created $relationships relationships");

}

with 'Modware::Loader::Role::Ontology::WithHelper';
__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

