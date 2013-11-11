package Modware::Loader::GFF3::Staging::Pg;
use namespace::autoclean;
use Digest::MD5 qw/md5/;
use feature qw/say/;
use Data::Dumper;
use Moose;
use Modware::Spec::GFF3::Analysis;
with 'Modware::Role::WithDataStash' => {
    'create_stash_for' => [
        qw/featureprop feature analysisfeature featureseq featureloc feature_synonym feature_relationship feature_dbxref/
    ]
};

has 'schema' => (
    is  => 'rw',
    isa => 'Bio::Chado::Schema',
);

has 'logger' => ( is => 'rw', isa => 'Log::Log4perl::Logger' );

sub create_tables {
    my ($self) = @_;
    for my $elem ( grep {/^create_table_temp/} $self->sqlmanager->elements ) {
        $self->schema->storage->dbh->do( $self->sqlmanager->retr($elem) );
    }
}

sub get_unique_feature_id {
    my ($self) = @_;
    my @row = $self->schema->storage->dbh->selectrow_array(
        qq{SELECT nextval('feature_feature_id_seq')});
    return $row[0];
}

sub create_synonym_pub_row {
    my ($self) = @_;
    my $dbh    = $self->schema->storage->dbh;
    my @row    = $dbh->selectrow_array(qq{SELECT nextval('pub_pub_id_seq')});
    my $rowid  = $row[0];

    my $pub_row = $self->schema->resultset('Pub::Pub')->create(
        {   uniquename => $rowid,
            pubplace   => 'GFF3-loader',
            title =>
                'This pubmed entry is for relating the usage of a given synonym to the publication in which it was used',
            type_id => $self->find_or_create_cvterm_row(
                {   cv     => 'pub',
                    cvterm => 'unpublished',
                    dbxref => 'unpublished',
                    db     => 'internal'
                }
            )->cvterm_id
        }
    );
    return $pub_row;
}

sub drop_tables {
}

sub create_indexes {
}

sub table2columns {
    my ( $self, $dbh, $table_name ) = @_;
    my $names = $dbh->selectall_arrayref(
        qq{SELECT distinct(column_name) FROM information_schema.columns where table_name = ?},
        { Slice => {} },
        ($table_name)
    );
    return map { $_->{column_name} } @$names;
}

sub bulk_load {
    my ($self) = @_;
    my $dbh = $self->schema->storage->dbh;
    for my $name (
        qw/feature analysisfeature featureseq featureloc feature_synonym feature_relationship
        feature_dbxref featureprop/
        )
    {
        my $table_name = 'temp_' . $name;
        my $index_api  = 'get_entry_from_' . $name . '_cache';
        my $count_api  = 'count_entries_in_' . $name . '_cache';
        next if !$self->$count_api;

        my $first_entry = $self->$index_api(0);
        my @columns     = $self->table2columns( $dbh, $table_name );
        my $stmt        = sprintf(
            "COPY %s(%s) FROM STDIN NULL AS ''",
            $table_name, join( ',', @columns ),
        );
        $dbh->do($stmt);
        my $itr_api = 'entries_in_' . $name . '_cache';
        for my $row ( $self->$itr_api ) {
            my @copydata;
            for my $cname (@columns) {
                if ( defined $row->{$cname} ) {
                    push @copydata, $row->{$cname};
                }
                else {
                    push @copydata, '';
                }
            }
            $dbh->pg_putcopydata( join( "\t", @copydata ) . "\n" );
        }
        $dbh->pg_putcopyend();
    }
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

# Fasta sequence comes in the following structure
# {
#    directive => 'FASTA',
#    seq_id => 'chr02',
#    sequence => 'ATGCACTCTCACGAT'
# }

sub add_data {
    my ( $self, $gff_hashref ) = @_;
    if ( exists $gff_hashref->{directive} ) {
        if ( $gff_hashref->{directive} eq 'FASTA' ) {
            $self->add_to_featureseq_cache(
                $self->make_featureseq_stash($gff_hashref) );
        }
    }
    else {
        my $feature_hashref = $self->make_feature_stash($gff_hashref);
        $self->add_to_feature_cache($feature_hashref);
        for my $name (qw/featureloc analysisfeature/) {
            my $api   = 'make_' . $name . '_stash';
            my $cache = 'add_to_' . $name . '_cache';
            $self->$cache( $self->$api( $gff_hashref, $feature_hashref ) );
        }
        for my $name (
            qw/feature_dbxref feature_synonym featureprop feature_relationship/
            )
        {
            my $api      = 'make_' . $name . '_stash';
            my $cache    = 'add_to_' . $name . '_cache';
            my $arrayref = $self->$api( $gff_hashref, $feature_hashref );
            $self->$cache(@$arrayref);
        }
    }
}

sub count_entries_in_staging {

}

with 'Modware::Loader::Role::WithStaging';
with 'Modware::Loader::Role::WithChadoHelper';
with 'Modware::Loader::Role::WithChadoGFF3Helper';

__PACKAGE__->meta->make_immutable;
1;

