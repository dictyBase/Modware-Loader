package Modware::Load::Command::oboclosure2chado;
use strict;
use namespace::autoclean;
use Moose;
use SQL::Library;
use Module::Load;
use File::ShareDir qw/module_dir module_file/;
use Bio::Chado::Schema;
extends qw/Modware::Load::Chado/;

has '+input' => (
    documentation =>
        'Name of chado closure file. You need owltools(http://code.google.com/p/owltools) to generate the closure file. First install  owltools(http://code.google.com/p/owltools/wiki/InstallOWLTools) using the jar and script.
                                Then run owltools <file.obo> --save-closure-for-chado <file.closure> to generate the closure file.',
    required => 1
);
has '+input_handler' => ( traits => [qw/NoGetopt/] );
has 'dry_run' => (
    is            => 'rw',
    isa           => 'Bool',
    lazy          => 1,
    default       => 0,
    documentation => 'Dry run do not save anything in database'
);

has 'pg_schema' => (
    is      => 'rw',
    isa     => 'Str',
    trigger => sub {
        my ( $self, $name ) = @_;
        $self->add_connect_hook("SET SCHEMA '$name'");
    },
    documentation =>
        'Name of postgresql schema where the ontology will be loaded, default is public, obviously ignored for other backend'
);

has 'sqllib' => (
    is        => 'rw',
    isa       => 'SQL::Library',
    predicate => 'has_sqllib',
    documentation =>
        'Path to sql library in INI format, by default picked up from the shared lib folder. Mostly a developer option.'
);

has 'namespace' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'Ontology namespace from which the closure is generated'
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;
    my $schema = $self->schema;
    my $backend = ucfirst lc( $schema->storage->sqlt_type );
    my $staging_class
        = 'Modware::Loader::TransitiveClosure::Staging::' . $backend;
    my $chado_class
        = 'Modware::Loader::TransitiveClosure::Chado::' . $backend;
    load $staging_class;
    load $chado_class;

    my $sqlmanager;
    if ( $self->has_sqllib ) {
        $sqlmanager = SQL::Library->new( { lib => $self->sqllib } );
    }
    else {
        $sqlmanager = SQL::Library->new(
            {   lib => module_file(
                    'Modware::Loader',
                    lc( $schema->storage->sqlt_type ) . '_transitive.lib'
                )
            }
        );
    }

    my $staging_loader = $staging_class->new(
        schema     => $schema,
        sqlmanager => $sqlmanager,
        namespace  => $self->namespace,
        logger     => $logger
    );
    my $chado_loader = $chado_class->new(
        sqlmanager => $sqlmanager,
        schema     => $schema,
        logger     => $logger
    );

    while ( my $line = $self->input_handler->getline() ) {
        $staging_loader->add_data($line);
    }

    $logger->debug("start loading in staging table");
    my $guard = $schema->txn_scope_guard;
    $staging_loader->create_tables;
    $staging_loader->bulk_load;
    my $entries = $staging_loader->count_entries_in_staging;
    $logger->debug(
        "done loading $entries->{temp_cvtermpath} entries in staging table");
    my $rows = $chado_loader->bulk_load;
    $logger->debug("loaded $rows entries in chado database");

    if ( $self->dry_run ) {
        $logger->info("Nothing saved in database");
    }
    else {
        $guard->commit;
    }
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

Modware::Load::Command::oboclosure2chado - Populate cvtermpath in chado database
 
