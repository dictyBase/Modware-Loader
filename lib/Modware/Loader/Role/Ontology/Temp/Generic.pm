package Modware::Loader::Role::Ontology::Temp::Generic;

use namespace::autoclean;
use Moose::Role;
use Encode;
use feature qw/say/;
use utf8;
with 'Modware::Role::WithDataStash' =>
    { create_stash_for => [qw/term relationship synonym comment/] };

# these hook to load data that are dependent on cvterm
has 'cvterm_dependencies' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    lazy    => 1,
    default => sub {
        return [ 'load_synonyms_in_staging', 'load_comments_in_staging' ];
    }
);

has 'post_cvterm_dependencies' => (
    is      => 'rw',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub {
        return {
            term    => 'TempCvterm',
            synonym => 'TempCvtermsynonym',
            comment => 'TempCvtermcomment'
        };
    }
);

sub load_cvterms_in_staging {
    my ( $self, $hooks ) = @_;
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
        $self->add_to_term_cache($insert_hash);
        $self->load_cache( 'term', 'TempCvterm', 1 );

        #hooks to run that depends on cvterms
        for my $hook ( @{ $self->cvterm_dependencies } ) {
            $self->$hook( $term, $insert_hash );
        }
    }

    # to load leftover cache in staging database
    while ( my ( $tag, $value ) = each %{ $self->post_cvterm_dependencies } )
    {
        $self->load_cache( $tag, $value );
    }
}

sub load_synonyms_in_staging {
    my ( $self, $term, $insert_hash ) = @_;
    my $synonym_insert_array
        = $self->get_synonym_term_hash( $term, $insert_hash );
    $self->add_to_synonym_cache(@$synonym_insert_array);
    $self->load_cache( 'synonym', 'TempCvtermsynonym', 1 );
}

sub load_comments_in_staging {
    my ( $self, $term, $insert_hash ) = @_;
    my $comment_insert_array
        = $self->get_comment_term_hash( $term, $insert_hash );
    if ( defined $comment_insert_array ) {
        $self->add_to_comment_cache(@$comment_insert_array);
        $self->load_cache( 'comment', 'TempCvtermcomment', 1 );
    }
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

sub get_insert_term_hash {
    my ( $self,  $term )      = @_;
    my ( $db_id, $accession ) = $self->_normalize_id( $term->id );
    my $insert_hash;
    $insert_hash->{accession} = $accession;
    $insert_hash->{db_id}     = $db_id;
    if ( my $text = $term->def->text ) {
        $insert_hash->{definition} = encode( "UTF-8", $text );
    }
    $insert_hash->{is_relationshiptype}
        = $term->isa('OBO::Core::RelationshipType') ? 1 : 0;
    $insert_hash->{name} = $term->name ? $term->name : $term->id;
    if ( $term->is_obsolete ) {
        $insert_hash->{is_obsolete} = 1;
        my $term_name
            = $insert_hash->{name} . sprintf( " (obsolete %s)", $term->id );
        $insert_hash->{name} = $term_name;
    }
    else {
        $insert_hash->{is_obsolete} = 0;
    }
    $insert_hash->{cmmnt} = $term->comment;
    return $insert_hash;
}

sub get_synonym_term_hash {
    my ( $self, $term, $term_insert_hash ) = @_;
    my $insert_array;
    for my $syn ( $term->synonym_set ) {
        push @$insert_array,
            {
            accession => $term_insert_hash->{accession},
            syn       => $syn->def->text,
            syn_scope_id =>
                $self->find_or_create_cvterm_namespace( $syn->scope,
                'synonym_type' )->cvterm_id,
            db_id => $term_insert_hash->{db_id}
            };
    }
    return $insert_array;
}

sub get_comment_term_hash {
    my ( $self, $term, $term_insert_hash ) = @_;
    if ( my $comment = $term->comment ) {
        my $insert_array;
        push @$insert_array,
            {
            accession => $term_insert_hash->{accession},
            comment   => $comment,
            comment_type_id =>
                $self->find_or_create_cvterm_namespace( 'comment',
                'cvterm_property_type' )->cvterm_id,
            db_id => $term_insert_hash->{db_id}
            };
        return $insert_array;
    }
}


sub load_cache {
    my ( $self, $cache, $result_class, $check_for_threshold ) = @_;
    if ($check_for_threshold) {
        my $count = 'count_entries_in_' . $cache . '_cache';
        return if $self->$count < $self->cache_threshold;
    }

    my $entries = 'entries_in_' . $cache . '_cache';
    my $clean   = 'clean_' . $cache . '_cache';
    $self->schema->resultset($result_class)->populate( [ $self->$entries ] );
    $self->$clean;
}


1;
