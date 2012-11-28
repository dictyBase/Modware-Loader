package Modware::Loader::Ontology;

use namespace::autoclean;
use Carp;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use DateTime::Format::Strptime;

has 'schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    writer  => 'set_schema',
    trigger => sub {
        my ( $self, $schema ) = @_;
        $self->_load_engine($schema);
        $self->transform_schema;
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

sub _load_engine {
    my ( $self, $schema ) = @_;
    $self->meta->make_mutable;
    my $engine = 'Modware::Loader::Role::Ontology::With'
        . ucfirst lc( $schema->storage->sqlt_type );
    ensure_all_roles( $self, $engine );
    $self->meta->make_immutable;
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

with 'Modware::Loader::Role::Ontology::WithHelper';
__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

