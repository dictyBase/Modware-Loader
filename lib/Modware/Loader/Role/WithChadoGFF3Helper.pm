package Modware::Loader::Role::WithChadoGFF3Helper;
use Moose::Role;
use namespace::autoclean;
use Digest::MD5 qw/md5/;
use feature qw/say/;
use Data::Dumper;
with 'Modware::Role::WithDataStash' =>
    { 'create_kv_stash_for' => [qw/analysis/] };

requires qw/create_synonym_pub_row get_unique_feature_id/;
requires
    qw/schema find_or_create_cvterm_row normalize_id find_or_create_dbxref_row find_cvterm_row get_organism_row/;

has 'organism' => ( is => 'rw', does => 'Modware::Role::WithOrganism' );
has [qw/organism_id analysis_id synonym_type_id synonym_pub_id/] => (
    is  => 'rw',
    isa => 'Int',
);
has 'analysis_spec' => (
    is        => 'rw',
    isa       => 'Modware::Spec::GFF3::Analysis',
    predicate => 'has_analysis_spec'
);
has 'synonym_spec' => (
    is        => 'rw',
    isa       => 'Modware::Spec::GFF3::Synonym',
    predicate => 'has_synonym_spec'
);
has 'uniquename_prefix' => ( is => 'rw', isa => 'Str', lazy => 1, default => 'auto');

sub initialize {
    my ($self) = @_;
    ## -- set organism
    $self->organism_id(
        $self->get_organism_row( $self->organism )->organism_id );

    ## -- set analysis
    if ( $self->has_analysis_spec ) {
        my $spec = $self->analysis_spec;
        my $rowhash = { program => $spec->program };
        for my $attr (qw/sourcename programversion/) {
            $rowhash->{$attr} = $spec->$attr if $spec->$attr;
        }
        my $row = $self->schema->resultset('Companalysis::Analysis')
            ->find_or_new($rowhash);
        if ( !$row->in_storage ) {
            $row->name( $spec->name ) if $spec->name;
            $row->insert();
        }
        $self->analysis_id( $row->analysis_id );
    }

    ## -- set synonym(alias)
    my ( $synonym_type_row, $synonym_pub_row );
    if ( $self->has_synonym_spec ) {
        ## if the synonym_spec object is provided with type use that to get the type_id
        my $synonym_type = $self->synonym_spec->type;
        $synonym_type_row = $self->find_or_create_cvterm_row(
            {   cv     => 'synonym_type',
                cvterm => $synonym_type,
                dbxref => $synonym_type,
                db     => 'internal'
            }
        );
        if ( my $pubmed = $self->synonym_spec->synonym_pubmed )
        {    # the pubmed id to use for synonym
            $synonym_pub_row = $self->schema->resultset('Pub::Pub')
                ->find( { uniquename => $pubmed } );
        }
        else {    # create a one with default value
            $synonym_pub_row = $self->create_synonym_pub_row;

        }
    }
    else {
        $synonym_type_row = $self->find_or_create_cvterm_row(
            {   cv     => 'synonym_type',
                cvterm => 'symbol',
                dbxref => 'symbol',
                db     => 'internal'
            }
        );

        $synonym_pub_row = $self->create_synonym_pub_row;
    }
    $self->synonym_type_id( $synonym_type_row->cvterm_id );
    $self->synonym_pub_id( $synonym_pub_row->pub_id );
}

sub make_featureseq_stash {
    my ( $self, $gff_seq_hashref ) = @_;
    my $insert_hash = {
        id      => $gff_seq_hashref->{seq_id},
        residue => $gff_seq_hashref->{sequence},
        md5     => md5( $gff_seq_hashref->{sequence} ),
        seqlen  => length( $gff_seq_hashref->{sequence} )
    };
    return $insert_hash;
}

sub make_feature_dbxref_stash {
    my ( $self, $gff_hashref, $feature_hashref ) = @_;
    return if not defined $gff_hashref->{attributes}->{Dbxref};
    my $insert_array;
    for my $xref ( @{ $gff_hashref->{attributes}->{Dbxref} } ) {
        my ( $db_id, $accession ) = $self->normalize_id($xref);
        push @$insert_array,
            {
            id     => $feature_hashref->{id},
            dbxref => $accession,
            db_id  => $db_id
            };
    }
    return $insert_array;
}

sub make_featureprop_stash {
    my ( $self, $gff_hashref, $feature_hashref ) = @_;
    my $insert_array;
    if ( defined $gff_hashref->{attributes}->{Note} ) {
        my $type_id = $self->find_or_create_cvterm_row(
            {   cvterm => 'Note',
                cv     => 'feature_property',
                dbxref => 'Note',
                db     => 'local'
            }
        )->cvterm_id;
        for my $note ( @{ $gff_hashref->{attributes}->{Note} } ) {
            push @$insert_array,
                {
                id       => $feature_hashref->{id},
                property => $note,
                type_id  => $type_id
                };
        }
    }

    for my $attr (
        grep { !/^[A-Z]{1}/ }
        keys %{ $gff_hashref->{attributes} }
        )
    {
        for my $value ( @{ $gff_hashref->{attributes}->{$attr} } ) {
            my $type_id = $self->find_or_create_cvterm_row(
                {   cvterm => $attr,
                    cv     => 'feature_property',
                    dbxref => $attr,
                    db     => 'local'
                }
            )->cvterm_id;
            push @$insert_array,
                {
                id       => $feature_hashref->{id},
                property => $value,
                type_id  => $type_id
                };
        }
    }
    return $insert_array;
}

sub make_feature_relationship_stash {
    my ( $self, $gff_hashref, $feature_hashref ) = @_;
    return if not defined $gff_hashref->{attributes}->{Parent};
    my $insert_array;
    for my $parent ( @{ $gff_hashref->{attributes}->{Parent} } ) {
        push @$insert_array, {
            id        => $feature_hashref->{id},
            parent_id => $parent,
            type_id   => $self->find_or_create_cvterm_row(
                {   cvterm => 'part_of',
                    cv     => 'sequence',
                    dbxref => 'part_of',
                    db     => 'local'
                }
            )->cvterm_id
        };
    }
    return $insert_array;
}

sub make_feature_synonym_stash {
    my ( $self, $gff_hashref, $feature_hashref ) = @_;
    return if not defined $gff_hashref->{attributes}->{Alias};
    my $insert_array;
    for my $alias ( @{ $gff_hashref->{attributes}->{Alias} } ) {
        push @$insert_array,
            {
            id      => $feature_hashref->{id},
            alias   => $alias,
            type_id => $self->synonym_type_id,
            pub_id  => $self->synonym_pub_id
            };
    }
    return $insert_array;
}

sub make_analysisfeature_stash {
    my ( $self, $gff_hashref, $feature_hashref ) = @_;
    return if not defined $gff_hashref->{score};
    my $insert_hash;
    if ( $self->analysis_id ) {
        $insert_hash = {
            id          => $feature_hashref->{id},
            score       => $gff_hashref->{score},
            analysis_id => $self->analysis_id
        };
        return $insert_hash;
    }
    my $analysis_key
        = $gff_hashref->{source} . '-' . $gff_hashref->{type} . '-1.0';
    my $analysis_id;
    if ( $self->has_analysis_row($analysis_key) ) {
        $analysis_id = $self->get_analysis_row($analysis_key)->analysis_id;
    }
    else {
        my $analysis_row
            = $self->schema->resultset('Companalysis::Analysis')->create(
            {   program => $gff_hashref->{source} . '-'
                    . $gff_hashref->{type},
                name => $gff_hashref->{source} . '-' . $gff_hashref->{type},
                programversion => '1.0'
            }
            );
        $self->set_analysis_row( $analysis_key, $analysis_row );
        $analysis_id = $analysis_row->analysis_id;
    }
    $insert_hash = {
        id          => $feature_hashref->{id},
        score       => $gff_hashref->{score},
        analysis_id => $analysis_id
    };
    $insert_hash;
}

sub make_featureloc_stash {
    my ( $self, $gff_hashref, $feature_hashref ) = @_;
    my $insert_hash = {
        id    => $feature_hashref->{id},
        seqid => $gff_hashref->{seq_id},
        start => $gff_hashref->{start} - 1,    #zero based coordinate in chado
        end   => $gff_hashref->{end}
    };
    if ( defined $gff_hashref->{strand} ) {
        $insert_hash->{strand} = $gff_hashref->{strand} eq '+' ? 1 : -1;
    }
    $insert_hash->{phase} = $gff_hashref->{phase}
        if defined $gff_hashref->{phase};
    return $insert_hash;
}

sub make_feature_stash {
    my ( $self, $gff_hashref ) = @_;
    my $insert_hash->{source_dbxref_id}
        = $self->find_or_create_dbxref_row( $gff_hashref->{source},
        'GFF_source' )->dbxref_id;
    $insert_hash->{type_id}
        = $self->find_cvterm_row( $gff_hashref->{type}, 'sequence' )
        ->cvterm_id;
    $insert_hash->{organism_id} = $self->organism_id;

    if ( defined $gff_hashref->{attributes}->{ID} ) {
        $insert_hash->{id} = $gff_hashref->{attributes}->{ID}->[0];
    }
    else {
        $insert_hash->{id}
            = $self->uniquename_prefix . $self->get_unique_feature_id;
    }
    if (defined $gff_hashref->{attributes}->{Name}) {
        $insert_hash->{name} = $gff_hashref->{attributes}->{Name}->[0];
    }
    return $insert_hash;
}

1;

__END__
