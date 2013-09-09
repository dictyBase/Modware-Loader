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

has 'include_metadata' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    documentation =>
        'Loads metadata of terms, that includes synonyms, dbxrefs, comments and alt_ids, by default they are skipped'
);

has '_metadata_apis' => (
    is      => 'ro',
    isa     => 'ArrayRef',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    default => sub {
        return [qw/comment synonyms xrefs alt_ids/];
    }
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
        logger       => $self->logger,
        app_instance => $self,
        chado        => $schema
    );
    $loader->load_namespaces($onto);

    #3. do upsert of relationship terms
    for my $term (
        ( @{ $onto->get_relationship_types }, @{ $onto->get_terms } ) )
    {
        my $return = $loader->update_or_create_term($term);
        if ( $self->include_metadata ) {
            if ( $return->[0] eq 'insert' ) {
                for my $name ( @{ $self->_metadata_apis } ) {
                    my $api = 'create_' . $name;
                    $loader->$api( $term, $return->[1] );
                }
            }
            else {
                for my $name ( @{ $self->_metadata_apis } ) {
                    my $create_api = 'create_' . $name;
                    my $delete_api = 'delete' . $name;
                    $loader->$delete_api( $term, $return->[1] );
                    $loader->$create_api( $term, $return->[1] );
                }
            }
        }
    }

    #5. commit terms
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
