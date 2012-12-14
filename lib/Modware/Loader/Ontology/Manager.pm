package Modware::Loader::Ontology::Manager;

use namespace::autoclean;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use Module::Load::Conditional qw/check_install/;

has 'logger' =>
    ( is => 'rw', isa => 'Log::Log4perl::Logger', writer => 'set_logger' );

has 'schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    writer  => 'set_schema',
    trigger => sub {
        my ( $self, $schema ) = @_;
        $self->_load_engine($schema);
    }
);

sub _load_engine {
    my ( $self, $schema ) = @_;
    $self->meta->make_mutable;
    my $engine = 'Modware::Loader::Role::Ontology::Chado::With'
        . ucfirst lc( $schema->storage->sqlt_type );
    if ( !check_install( module => $engine ) ) {
        $engine = 'Modware::Loader::Role::Ontology::Chado::Generic';
    }
    ensure_all_roles( $self, $engine );
    $self->meta->make_immutable;
}

has 'connect_info' => (
    is      => 'rw',
    isa     => 'Modware::Storage::Connection',
    writer  => 'set_connect_info',
    trigger => sub {
        my ($self) = @_;
        $self->_around_connection;
    }
);

sub _around_connection {
    my ($self)       = @_;
    my $connect_info = $self->connect_info;
    my $extra_attr   = $connect_info->extra_attribute;

    my $opt = {
        on_disconnect_do => sub { $self->drop_on_delete_statements(@_) },
        on_connect_do    => sub { $self->create_on_delete_statements(@_) }
    };
    $opt->{on_connect_call} = $extra_attr->{on_connect_do}
        if defined $extra_attr->{on_connect_do};

    $self->schema->connection( $connect_info->dsn, $connect_info->user,
        $connect_info->password, $connect_info->attribute, $opt );
    $self->schema->storage->debug( $connect_info->schema_debug );
}

has 'cvrow_in_db' =>
    ( is => 'rw', isa => 'DBIx::Class::Row', writer => 'set_cvrow_in_db' );

sub is_ontology_in_db {
    my ( $self, $namespace, $partial_lookup ) = @_;
    my $query = { name => $namespace };
    if ($partial_lookup) {
        $query = { name => { 'like' => $query . '%' } };
    }
    my $row = $self->schema->resultset('Cv::Cv')->find($query);
    if ($row) {
        $self->set_cvrow_in_db($row);
        return $row;
    }
}

sub delete_ontology {
    my ($self)  = @_;
    my $cv_id   = $self->cvrow_in_db->cv_id;
    my $storage = $self->schema->storage;

    $storage->dbh_do( sub { $self->delete_cvterms(@_) }, $cv_id );
    my $dbxrefs = $storage->dbh_do( sub { $self->delete_dbxrefs(@_) } );
    $self->logger->debug("deleted $dbxrefs dbxrefs");

}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

