use Test::More qw/no_plan/;
use Bio::Chado::Schema;
use Test::Exception;
use File::ShareDir qw/module_file/;
use Test::Chado qw/chado_schema drop_schema/;
use Test::Chado::Common qw/:all/;
use Digest::MD5 qw/md5/;
use Modware::Spec::GFF3::Analysis;
use Modware::DataSource::Chado::Organism;

{

    package MyChadoGFF3;
    use Moose;

    has 'schema' => ( is => 'rw', isa => 'DBIx::Class::Schema' );
    has 'target_type' =>
        ( is => 'ro', isa => 'Str', default => 'polypeptide' );

    sub get_unique_feature_id { return 1555557 }

    sub create_synonym_pub_row {
        my ($self) = @_;
        my $row = $self->schema->resultset('Pub::Pub')->create(
            {   uniquename => 'GFF3-synonym-pub-test',
                type_id    => $self->find_or_create_cvterm_row(
                    {   cv     => 'pub',
                        cvterm => 'unpublished',
                        dbxref => 'unpublished',
                        db     => 'internal'
                    }
                )->cvterm_id
            }
        );
        return $row;
    }
    with 'Modware::Loader::Role::WithChadoHelper';
    with 'Modware::Loader::Role::WithChadoGFF3Helper';

    1;
}

subtest 'run the setup' => sub {
    my $tmp_schema = chado_schema( load_fixture => 1 );
    my $schema
        = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );

    my $helper = new_ok('MyChadoGFF3');
    $helper->schema($schema);
    $helper->organism(
        Modware::DataSource::Chado::Organism->new(
            genus   => 'Homo',
            species => 'sapiens'
        )
    );
    $helper->analysis_spec(
        Modware::Spec::GFF3::Analysis->new(
            program        => 'GFF3-staging-test',
            programversion => '1.3',
            sourcename     => 'GFF3-tester',
            name           => 'GFF3-test'
        )
    );
    lives_ok { $helper->initialize } 'should run initialize';
    for my $name (qw/organism analysis synonym_type synonym_pub/) {
        my $api = $name . '_id';
        like( $helper->$api, qr/\d+/, "should have $name id" );
    }
    is( $schema->resultset('Companalysis::Analysis')
            ->find( { analysis_id => $helper->analysis_id } )->program,
        'GFF3-staging-test',
        'should match analysis program'
    );
    has_cv( $schema, 'synonym_type', 'should have synonym_type cv' );
    has_cvterm( $schema, 'symbol', 'should have symbol cvterm' );
    has_dbxref( $schema, 'symbol', 'should have symbol dbxref' );
    is( $schema->resultset('Pub::Pub')
            ->find( { pub_id => $helper->synonym_pub_id } )->uniquename,
        'GFF3-synonym-pub-test',
        'should match publication for linking synonym'
    );
    has_cv( $schema, 'pub', 'should have pub cv' );
    has_cvterm( $schema, 'unpublished', 'should have unpublished cvterm' );
    has_dbxref( $schema, 'unpublished', 'should have unpublished dbxref' );

    drop_schema();
};

subtest 'make staging compatible hash data structure from GFF3' => sub {
    my $tmp_schema = chado_schema( load_fixture => 1 );
    my $schema
        = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );
    my $helper = new_ok('MyChadoGFF3');
    $helper->schema($schema);
    $helper->organism(
        Modware::DataSource::Chado::Organism->new(
            genus   => 'Homo',
            species => 'sapiens'
        )
    );
    lives_ok { $helper->initialize } 'should run initialize';

    my $gff_hashref = {
        seq_id     => 'DDB0166986',
        source     => 'Sequencing Center',
        type       => 'chromosome',
        start      => 1,
        end        => 8467571,
        attributes => {
            ID   => ['DDB0166986'],
            Name => ['chr1']
        }
    };
    my $insert_hashref;
    lives_ok { $insert_hashref = $helper->make_feature_stash($gff_hashref) }
    'should run make_feature_stash';
    ok( defined $insert_hashref->{$_}, "should have $_ in the hashref" )
        for qw(source_dbxref_id type_id organism_id);
    is( $insert_hashref->{id}, 'DDB0166986', 'should match the ID value' );
    is( $insert_hashref->{name}, 'chr1', 'should match the Name value' );

    delete $gff_hashref->{attributes}->{ID};
    lives_ok { $insert_hashref = $helper->make_feature_stash($gff_hashref) }
    'should run make_feature_stash';
    is( $insert_hashref->{id}, 'auto1555557',
        'should have auto prefix for id value' );

    $gff_hashref = {
        seq_id     => 'DDB0166986',
        source     => 'dictyBase',
        type       => 'gene',
        start      => 3289127,
        end        => 3312764,
        strand     => '+',
        attributes => {
            ID   => ['DDB_G0273713'],
            Name => ['aslA-2'],
        }
    };
    lives_ok { $insert_hashref = $helper->make_feature_stash($gff_hashref) }
    'should run make_feature_stash';
    my $featureloc_hashref;
    lives_ok {
        $featureloc_hashref
            = $helper->make_featureloc_stash( $gff_hashref, $insert_hashref );
    }
    'should run make_featureloc_stash';
    is_deeply(
        $featureloc_hashref,
        {   id     => 'DDB_G0273713',
            seqid  => 'DDB0166986',
            start  => 3289126,
            stop   => 3312764,
            strand => 1
        },
        'should have the expected featureloc hashref'
    );

    $gff_hashref->{score} = 43.2;
    my $analysis_hashref;
    lives_ok {
        $analysis_hashref = $helper->make_analysisfeature_stash( $gff_hashref,
            $insert_hashref );
    }
    'should run make_analysisfeature_stash';
    like( $analysis_hashref->{analysis_id},
        qr/\d+/, 'should match analysis_id' );
    is( $analysis_hashref->{id}, $insert_hashref->{id}, 'should have id' );
    is( $analysis_hashref->{score},
        $gff_hashref->{score}, 'should have score' );
    my $analysis_row;
    lives_ok {
        $analysis_row = $schema->resultset('Companalysis::Analysis')
            ->find( { analysis_id => $analysis_hashref->{analysis_id} } );
    }
    'should fetch analysis row from database';
    is( $analysis_row->programversion, '1.0', 'should match programversion' );
    is( $analysis_row->name,
        $gff_hashref->{source} . '-' . $gff_hashref->{type},
        'should match analysis name'
    );

    $gff_hashref->{attributes}->{Target} = ['BC0456 178 1828 +'];
    my $target_hashref;
    lives_ok {
        $target_hashref = $helper->make_feature_target_stash( $gff_hashref,
            $insert_hashref );
    }
    'should run make_feature_target_stash';
    my $expected_target_hashref = {
        target_hashref => {
            source_dbxref_id => $insert_hashref->{source_dbxref_id},
            type_id          => $schema->resultset('Cv::Cvterm')
                ->find(
                { 'cv.name' => 'sequence', 'name' => $helper->target_type },
                { join => 'cv' } )->cvterm_id,
            organism_id => $insert_hashref->{organism_id},
            id          => 'BC0456'
        },
        alignment_hashref => {
            source_dbxref_id => $insert_hashref->{source_dbxref_id},
            organism_id      => $insert_hashref->{organism_id},
            type_id          => $insert_hashref->{type_id},
            id               => $insert_hashref->{id},
            name             => $insert_hashref->{name}
        },
        feature_analysis => $analysis_hashref,
        featureloc       => $featureloc_hashref,
        query_featureloc => {
            id     => $insert_hashref->{id},
            seqid  => 'BC0456',
            start  => 178,
            stop   => 1828,
            rank   => 1,
            strand => 1
        },
        feature_relationship => undef
    };
    is_deeply( $target_hashref, $expected_target_hashref,
        'should match the target hashref' );

    my $featureseq_row;
    lives_ok {
        $featureseq_row = $helper->make_featureseq_stash(
            {   seq_id   => 'DDB0166986',
                sequence => 'ATGACTCTAATATAGCACACGTGATATATAGAC'
            }
        );
    }
    'should run make_featureseq_stash';
    is_deeply(
        $featureseq_row,
        {   id      => 'DDB0166986',
            residue => 'ATGACTCTAATATAGCACACGTGATATATAGAC',
            md5     => md5('ATGACTCTAATATAGCACACGTGATATATAGAC'),
            seqlen  => length('ATGACTCTAATATAGCACACGTGATATATAGAC')
        },
        'should match the featureseq structure'
    );

    drop_schema();
};

subtest 'make staging compatible array data structure from GFF3' => sub {
    my $tmp_schema = chado_schema( load_fixture => 1 );
    my $schema
        = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );
    my $helper = new_ok('MyChadoGFF3');
    $helper->schema($schema);
    $helper->organism(
        Modware::DataSource::Chado::Organism->new(
            genus   => 'Homo',
            species => 'sapiens'
        )
    );

    $gff_hashref = {
        seq_id     => 'DDB0166986',
        source     => 'dictyBase',
        type       => 'gene',
        start      => 3289127,
        end        => 3312764,
        strand     => '+',
        attributes => {
            ID    => ['DDB_G0273713'],
            Name  => ['aslA-2'],
            Alias => [ 'aslA', 'asl' ]
        }
    };
    lives_ok { $helper->initialize } 'should run initialize';
    my $insert_hashref;
    lives_ok { $insert_hashref = $helper->make_feature_stash($gff_hashref) }
    'should run make_feature_stash';
    my $synonym_arrayref;
    lives_ok {
        $synonym_arrayref = $helper->make_feature_synonym_stash( $gff_hashref,
            $insert_hashref );
    }
    'should run make_feature_synonym_stash';
    is_deeply(
        $synonym_arrayref,
        [   {   id      => $insert_hashref->{id},
                alias   => 'aslA',
                type_id => $helper->synonym_type_id,
                pub_id  => $helper->synonym_pub_id
            },
            {   id      => $insert_hashref->{id},
                alias   => 'asl',
                type_id => $helper->synonym_type_id,
                pub_id  => $helper->synonym_pub_id
            }
        ],
        'should match synonym arrayref structure'
    );

    push @{ $gff_hashref->{attributes}->{Dbxref} }, 'UniProtKB:P54673',
        'EAL67965';
    my $dbxref_arrayref;
    lives_ok {
        $dbxref_arrayref = $helper->make_feature_dbxref_stash( $gff_hashref,
            $insert_hashref );
    }
    'should run make_feature_dbxref_stash';
    is_deeply(
        $dbxref_arrayref,
        [   {   id     => $insert_hashref->{id},
                dbxref => 'P54673',
                db_id  => $schema->resultset('General::Db')
                    ->find( { name => 'UniProtKB' } )->db_id
            },
            {   id     => $insert_hashref->{id},
                dbxref => 'EAL67965',
                db_id  => $schema->resultset('General::Db')
                    ->find( { name => 'internal' } )->db_id
            }
        ]
    );

    push @{ $gff_hashref->{attributes}->{Note} },
        'There are two copies of this gene';
    push @{ $gff_hashref->{attributes}->{product} },
        'putative acetyl-CoA synthatase';
    push @{ $gff_hashref->{attributes}->{Gap} }, 'M3 I1 M2 F1 M4';
    my $prop_arrayref;
    lives_ok {
        $prop_arrayref = $helper->make_featureprop_stash( $gff_hashref,
            $insert_hashref );
    }
    'should run make_featureprop_stash';
    is_deeply(
        $prop_arrayref,
        [   {   id       => $insert_hashref->{id},
                property => 'There are two copies of this gene',
                type_id  => $schema->resultset('Cv::Cvterm')
                    ->find(
                    { 'cv.name' => 'feature_property', 'name' => 'Note' },
                    { join      => 'cv' } )->cvterm_id
            },
            {   id       => $insert_hashref->{id},
                property => 'M3 I1 M2 F1 M4',
                type_id  => $schema->resultset('Cv::Cvterm')
                    ->find(
                    { 'cv.name' => 'feature_property', 'name' => 'Gap' },
                    { join      => 'cv' } )->cvterm_id
            },
            {   id       => $insert_hashref->{id},
                property => 'putative acetyl-CoA synthatase',
                type_id  => $schema->resultset('Cv::Cvterm')->find(
                    { 'cv.name' => 'feature_property', 'name' => 'product' },
                    { join      => 'cv' }
                )->cvterm_id
            }
        ]
    );

    push @{ $gff_hashref->{attributes}->{Parent} }, 'DDB_G0273713',
        'DDB_G0273719';
    my $frel_hashref;
    lives_ok {
        $frel_hashref
            = $helper->make_feature_relationship_stash( $gff_hashref,
            $insert_hashref );
    }
    'should run make_relationship_stash';
    my $type_id
        = $schema->resultset('Cv::Cvterm')
        ->find( { 'cv.name' => 'sequence', 'name' => 'part_of' },
        { join => 'cv' } )->cvterm_id;
    is_deeply(
        $frel_hashref,
        [   {   id        => $insert_hashref->{id},
                parent_id => 'DDB_G0273713',
                type_id   => $type_id
            },
            {   id        => $insert_hashref->{id},
                parent_id => 'DDB_G0273719',
                type_id   => $type_id
            },
        ]
    );
};
