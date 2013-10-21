package Modware::Loader::GFF3::Staging::Sqlite;
use namespace::autoclean;
use Moose;
use Modware::Spec::GFF3::Analysis;
with 'Modware::Role::WithDataStash' => {
    'create_stash_for'    => [qw/feature analysis/],
    'create_kv_stash_for' => [qw/analysis/]
};

has 'schema' => (
    is  => 'rw',
    isa => 'Bio::Chado::Schema',
);

has 'logger'   => ( is => 'rw', isa  => 'Log::Log4perl::Logger' );
has 'organism' => ( is => 'rw', does => 'Modware::Role::WithOrganism' );
has [qw/organism_id analysis_id/] => (
    is  => 'rw',
    isa => 'Int',
);
has 'analysis_spec' => (
    is        => 'rw',
    isa       => 'Modware::Spec::GFF3::Analysis',
    predicate => 'has_analysis_spec'
);
has 'synonym_spec' => (
    is => 'rw',
    isa => 'Modware::Spec::GFF3::Synonym',
    predicate => 'has_synonym_spec'
);

sub create_tables {
    my ($self) = @_;
    for my $elem ( grep {/^create_table_temp/} $self->sqlmanager->elements ) {
        $self->schema->storage->dbh->do( $self->sqlmanager->retr($elem) );
    }
}

sub initialize {
    my ($self) = @_;
    $self->organism_id(
        $self->get_organism_row( $self->organism )->organism_id );
    return if !$self->has_analysis_spec;

    my $spec = $self->analysis_spec;
    my $rowhash = { program => $spec->program };
    for my $attr (qw/sourcename programversion/) {
        $rowhash->{$attr} = $spec->$attr if $spec->$attr;
    }
    my $row = $self->schema->resultset('Companalysis::Analysis')
        ->find_or_new($rowhash);
    if ( !$row->in_storgae ) {
        $row->name( $spec->name ) if $spec->name;
        $row->insert();
    }
    $self->analysis_id( $row->analysis_id );
}

sub drop_tables {
}

sub create_indexes {
}

sub bulk_load {
    my ($self) = @_;
}

# Each data row is a hashref with the following structure....
#{   seq_id     => 'chr02',
#source     => 'AUGUSTUS',
#type       => 'transcript',
#start      => '23486',
#end        => '48209',
#score      => '0.02',
#strand     => '+',
#phase      => undef,
#attributes => {
#ID     => [ 'chr02.g3.t1' ],
#Parent => [ 'chr02.g3' ],
#},
#}
sub add_data {
    my ( $self, $gff_hashref ) = @_;
    my $feature_hash = $self->make_feature_hash($gff_hashref);
    $self->add_to_feature_cache($feature_hash);
}

sub make_feature_synonym_hash {
    my ( $self, $gff_hashref, $feature_hash ) = @_;
}

sub make_analysisfeature_hash {
    my ( $self, $gff_hashref, $feature_hash ) = @_;
    return if not defined $gff_hashref->{score};
    my $insert_hash;
    if ( $self->analysis_id ) {
        $insert_hash = {
            id          => $feature_hash->{id},
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
        id          => $feature_hash->{id},
        score       => $gff_hashref->{score},
        analysis_id => $analysis_id
    };
    $insert_hash;
}

sub make_featureloc_hash {
    my ( $self, $gff_hashref, $feature_hash ) = @_;
    my $insert_hash = {
        id    => $feature_hash->{id},
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

sub make_feature_hash {
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
        if ( defined $gff_hashref->{attributes}->{Name} ) {
            $insert_hash->{Name} = $gff_hashref->{attributes}->{Name}->[0];
        }
    }
    else {
        $insert_hash->{id}
            = 'auto-' . $gff_hashref->{attributes}->{Name}->[0];
        $insert_hash->{Name} = $gff_hashref->{attributes}->{Name}->[0];
    }
    return $insert_hash;

}

sub count_entries_in_staging {

}

with 'Modware::Loader::Role::WithStaging';
with 'Modware::Loader::Role::WithChadoHelper';
__PACKAGE__->meta->make_immutable;
1;

