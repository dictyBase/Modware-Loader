package Modware::Load::Command::bioportalobo2chado;
use strict;
use namespace::autoclean;
use Moose;
use BioPortal::WebService;
use Modware::Loader::Ontology;
use OBO::Parser::OBOParser;
use feature qw/say/;
extends qw/Modware::Load::Chado/;

has 'apikey' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'An API key for bioportal'
);

has 'ontology' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'Name of the ontology for loading in Chado'
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;

    my $bioportal = BioPortal::WebService->new( apikey => $self->apikey );
    my $downloader = $bioportal->download( $self->ontology );
    if ( !$downloader->is_obo_format ) {
        $logger->logcroak( $self->ontology,
            ' is not available in OBO format' );
    }

    my $loader   = Modware::Loader::Ontology->new;
    my $ontology = OBO::Parser::OBOParser->new->work( $downloader->filename );
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
    $guard->commit;
}

1;

__END__

=head1 NAME

Modware::Load::Command::bioportalobo2chado -  Load ontology from NCBO bioportal to chado database
 
