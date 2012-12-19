package Modware::Loader::Role::Ontology::Temp::Generic;

use namespace::autoclean;
use Moose::Role;

sub load_cvterms_in_staging {
    my ($self)        = @_;
    my $onto          = $self->ontology;
    my $schema        = $self->schema;
    my $default_cv_id = $self->get_cvrow( $onto->default_namespace )->cv_id;

    #Term
    for my $term ( @{ $onto->get_relationship_types }, @{ $onto->get_terms } )
    {
        my $insert_hash = $self->get_insert_term_hash($term);
        $insert_hash->{cv_id}
            = $term->namespace
            ? $self->find_or_create_cvrow( $term->namespace )->cv_id
            : $default_cv_id;

        #synonyms
        my $synonym_insert_array
            = $self->get_synonym_term_hash( $term, $insert_hash );
        $self->add_to_term_cache($insert_hash);
        $self->add_to_synonym_cache($_) for @$synonym_insert_array;

        $self->load_cache( 'term',    'TempCvterm' );
        $self->load_cache( 'synonym', 'TempCvtermsynonym' );
    }

    $self->load_cache( 'term',    'TempCvterm' );
    $self->load_cache( 'synonym', 'TempCvtermsynonym' );

}

sub load_relationship_in_staging {
    my ($self) = @_;
    my $onto   = $self->ontology;
    my $schema = $self->schema;

    for my $rel ( @{ $onto->get_relationships } ) {
        my @object  = $self->_normalize_id( $rel->head->id );
        my @subject = $self->_normalize_id( $rel->tail->id );
        my @type    = $self->_normalize_id( $rel->type );

        $self->add_to_relationship_cache(
            {   object_db_id  => $object[0],
                object        => $object[1],
                subject_db_id => $subject[0],
                subject       => $subject[1],
                type_db_id    => $type[0],
                type          => $type[1]
            }
        );
        if ( $self->count_entries_in_relationship_cache
            >= $self->cache_threshold )
        {
            $schema->resultset('TempCvtermRelationship')
                ->populate( [ $self->entries_in_relationship_cache ] );
            $self->clean_relationship_cache;
        }
    }
    if ( $self->count_entries_in_relationship_cache ) {
        $schema->resultset('TempCvtermRelationship')
            ->populate( [ $self->entries_in_relationship_cache ] );
        $self->clean_relationship_cache;
    }
}

sub load_alt_ids_in_staging {
}

sub load_cache {
    my ( $self, $cache, $result_class ) = @_;
    my $count = 'count_entries_in_' . $cache . '_cache';
    return if $self->$count < $self->cache_threshold;

    my $entries = 'entries_in_' . $cache . '_cache';
    my $clean   = 'clean_' . $cache . '_cache';
    $self->schema->resultset($result_class)->populate( [ $self->$entries ] );
    $self->$clean;
}

1;
