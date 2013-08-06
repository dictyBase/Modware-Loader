package Modware::Load::Command::obo2chado;
use strict;
use namespace::autoclean;
use Moose;
use Modware::Loader::Ontology;
use OBO::Parser::OBOParser;
use feature qw/say/;
extends qw/Modware::Load::Chado/;

has '+input' => ( documentation => 'Name of the obo file', required => 1 );
has '+input_handler' => ( traits => [qw/NoGetopt/] );
has 'dry_run' => (
    is            => 'rw',
    isa           => 'Bool',
    lazy          => 1,
    default       => 0,
    documentation => 'Dry run do not save anything in database'
);

has 'pg_schema' => (
    is  => 'rw',
    isa => 'Str',
    predicate => 'has_pg_schema',
    documentation =>
        'Name of postgresql schema where the ontology will be loaded, default is public, obviously ignored for other backend'
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;
    my $loader = Modware::Loader::Ontology->new( app_instance => $self );

    $logger->info( "start parsing file ", $self->input );
    my $ontology = OBO::Parser::OBOParser->new->work( $self->input );
    $logger->info("parsing done");

    $loader->set_logger($logger);
    $loader->set_ontology($ontology);
    $loader->set_schema( $self->schema );
    $loader->set_connect_info( $self->connect_info );

    #check for presence of cvprop ontology
    if ( !$loader->is_cvprop_present ) {
        $loader->finish;
        $logger->logdie("cvprop ontology is not loaded!!! cannot continue");
    }

    #enable transaction
    # check if it is a new version
    if ( $loader->is_ontology_in_db() ) {
        if ( !$loader->is_ontology_new_version() ) {
            $loader->finish;
            $logger->logdie(
                "This version of ontology already exist in database");
        }
    }

    my $guard = $self->schema->txn_scope_guard;
    $loader->store_metadata;
    $loader->find_or_create_namespaces;

    #transaction for loading in staging temp tables
    $logger->info("start loading in staging");
    $loader->load_data_in_staging;

    $logger->info("start loading in chado");
    $loader->merge_ontology;
    if ( $self->dry_run ) {
        $logger->info("Nothing saved in database");
    }
    else {
        $guard->commit;
    }
    $loader->finish;
    $logger->info( "loaded ", $self->input, " in chado" );
}
1;

__END__

=head1 NAME

Modware::Load::Command::obo2chado -  Load ontology from obo flat file to chado database
 
