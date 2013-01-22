package Modware::Load::Command::bioportalobo2chado;
use strict;
use namespace::autoclean;
use Moose;
use BioPortal::WebService;
use Modware::Loader::Ontology;
use OBO::Parser::OBOParser;
use feature qw/say/;
extends qw/Modware::Load::Chado/;


has '+input' => ( traits => [qw/NoGetopt/]);
has '+input_handler' => ( traits => [qw/NoGetopt/] );

has 'dry_run' => (
    is            => 'rw',
    isa           => 'Bool',
    lazy          => 1,
    default       => 0,
    documentation => 'Dry run do not save anything in database'
);

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

    $logger->info("downloaded ", $self->ontology ,  " in ", $downloader->filename);


    my $loader = Modware::Loader::Ontology->new;
    $logger->info( "start parsing file ", $downloader->filename );
    my $ontology = OBO::Parser::OBOParser->new->work( $downloader->filename );
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
    $logger->info( "loaded ", $downloader->filename, " in chado" );

}

1;

__END__

=head1 NAME

Modware::Load::Command::bioportalobo2chado -  Load ontology from NCBO bioportal to chado database
 
