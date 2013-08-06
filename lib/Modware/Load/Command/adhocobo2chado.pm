package Modware::Load::Command::adhocobo2chado;
use strict;
use namespace::autoclean;
use Moose;
use OBO::Parser::OBOParser;
use Modware::Loader::Adhoc::Ontology;
extends qw/Modware::Load::Chado/;

has 'pg_schema' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'Name of postgresql schema where the ontology will be loaded, default is public and makes no sense to set it for any other backend'
);

sub execute {
    my ($self) = @_;

    #1. read the file
    my $io   = OBO::Parser::OBOParser->new;
    my $onto = $io->work( $self->input );

    my $schema = $self->schema;
    my $guard  = $schema->txn_scope_guard;

    #2a. Get a loader object and set it up
    my $loader = Modware::Loader::Adhoc::Ontology->new(
        logger => $self->logger,
        app_instance => $self,
        chado  => $schema
    );
    $loader->load_namespaces($onto);

    #3. do upsert of relationship terms
    for my $term ( @{ $onto->get_relationship_types } ) {

        #get list of new relationship terms
        #   It wraps around two methods
        #   if (find_term($term)) {
        #	  update_term($term, $term_from_db);
        #   }
        #   else {
        #     insert_term($term);
        #}
        $loader->update_or_create_term($term);
    }

    #4. do upsert of terms
    $loader->update_or_create_term($_) for @{ $onto->get_terms };

    #5. do insert of relationships
    $guard->commit;

    my $guard2 = $schema->txn_scope_guard;
    $loader->create_relationship($_) for @{ $onto->get_relationships };
    $guard2->commit;

}

1;

__END__

=head1 NAME

Modware::Load::Command::adhocobo2chado -  Load an adhoc ontology in chado database 
 

=head1 DESCRIPTION

 The application module is designed to load B<adhoc> ontologies such as those are
 available from GMOD's chado distribution primary to be used by other bigger ontologies
 and features to store their properties(in cvprop/featureprop table).
 
 This loader will skip cv properties,  secondary ids, synonyms,  relation attributes and
 will not update relationships.

 B<ABSOLUTELY DO NOT USE> this for bigger and complicated ontologies which are used to
 define annotations.
