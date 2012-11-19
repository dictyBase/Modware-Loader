package Modware::Load::Command::adhocobo2chado;
use strict;
use namespace::autoclean;
use Moose;
use Bio::OntologyIO;
extends qw/Modware::Load::Chado/;

has '_is_relationship' =>
    ( is => 'ro', lazy => 1, default => 1, isa => 'Bool' );

sub execute {
    my ($self) = @_;

    #1. read the file
    my $io = Bio::OntologyIO->new(
        -fh     => $self->input_handler,
        -format => 'obo'
    );
    my $onto = $io->next_ontology;

    #2. Create or select the global namespaces for cv and db.
    my $schema = $self->schema;
    my $global_cv = $schema->resultset('Cv::Cv')
        ->find_or_create( { name => $onto->name } );
    my $global_db = $schema->resultset('General::Db')
        ->find_or_create( { name => '_global' } );

    #2a. Get a loader object and set it up
    my $loader = Modware::Loader::Adhoc::Ontology->new;
    $loader->chado($schema);
    $loader->cv_namespace($global_cv);
    $loader->db_namespace($global_db);

    #3. do upsert of relationship terms
    for my $term ( $onto->get_predicate_terms ) {

        #get list of new relationship terms
        #   It wraps around two methods
        #   if (find_term($term)) {
        #	  update_term($term, $term_from_db);
        #   }
        #   else {
        #     insert_term($term);
        #}
        $loader->update_or_create_term( $term, $self->is_relationship );
    }

    #4. do upsert of terms
    $loader->update_or_create_term($term) for $onto->get_all_terms;

    #5. do upsert of relationships

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
