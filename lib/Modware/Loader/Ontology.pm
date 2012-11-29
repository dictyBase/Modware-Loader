package Modware::Loader::Ontology;

use namespace::autoclean;
use Carp;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use feature qw/switch/;
use DateTime::Format::Strptime;

has 'schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    writer  => 'set_schema',
    trigger => sub {
        my ($self) = @_;
        $self->_load_engine;
        $self->_around_connection;
        $self->_check_cvprop_or_die;
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
            pattern  => '%Y-%m-%d',
            on_error => 'croak'
        );
    }
);

sub _around_connection {
    my ($self) = @_;
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
    if ( $self->exists_cvrow($cvname) ) {
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
            my $api = ( $method eq 'remark' ) ? $method . 's' : $method;
            $row->value( $onto->$api );
            $row->update;
        }
    }
    else {
        $cvrow->insert;
        my $cvprop_id = $self->get_cvrow('cv_property')->cv_id;
        for my $method ( ( 'date', 'data_version', 'saved_by', 'remark' ) ) {
            ( my $cvterm = $method ) =~ s{_}{-};
            my $api = ( $method eq 'remark' ) ? $method . 's' : $method;
            $cvrow->add_to_cvprops(
                {   value   => $onto->$api,
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

with 'Modware::Loader::Role::Ontology::WithHelper';
__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

