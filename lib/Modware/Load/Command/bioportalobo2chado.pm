package Modware::Load::Command::bioportalobo2chado;
use strict;
use namespace::autoclean;
use Moose;
use BioPortal::WebService;
use Modware::Loader::Ontology;
use OBO::Parser::OBOParser;
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
    $loader->set_ontology($ontology);
    $loader->set_schema( $self->schema );

	#enable transaction 
    my $guard  = $self->schema->txn_scope_guard;
    # check if it is a new version
    if ( $loader->is_ontology_in_db() ) {
        if ( !$loader->is_ontology_new_version() ) {
            $logger->logcroak(
                "This version of ontology already exist in database");
        }
    }
    $loader->store_metadata;
    $loader->find_or_create_namespaces;
    $guard->commit;
}

1;

__END__

=head1 NAME

Modware::Load::Command::bioportalobo2chado -  Load ontology from NCBO bioportal to chado database
 
