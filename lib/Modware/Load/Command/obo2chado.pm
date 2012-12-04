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

sub execute {
    my ($self)   = @_;
    my $logger   = $self->logger;
    my $loader   = Modware::Loader::Ontology->new;
    my $ontology = OBO::Parser::OBOParser->new->work( $self->input );
    $loader->set_logger($logger);
    $loader->set_ontology($ontology);
    $loader->set_schema( $self->schema );
    $loader->set_connect_info( $self->connect_info );

    #enable transaction
    # check if it is a new version
    if ( $loader->is_ontology_in_db() ) {
        if ( !$loader->is_ontology_new_version() ) {
            $logger->logdie(
                "This version of ontology already exist in database");
        }
    }

    my $guard = $self->schema->txn_scope_guard;
    $loader->store_metadata;
    $loader->find_or_create_namespaces;

    #transaction for loading in staging temp tables
    $loader->prepare_data_for_loading;

    $logger->info(
        sprintf "terms:%d\trelationships:%d in staging tables",
        $loader->entries_in_staging('TempCvterm'),
        $loader->entries_in_staging('TempCvtermRelationship')
    );

    $loader->merge_ontology;

    if ( $self->dry_run ) {
        $logger->info("Nothing saved in database");
    }
    else {
        $guard->commit;
    }

    1;

__END__

=head1 NAME

Modware::Load::Command::obo2chado -  Load ontology from obo flat file to chado database
 
