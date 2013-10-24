use Test::More qw/no_plan/;
use Bio::Chado::Schema;
use Test::Exception;
use File::ShareDir qw/module_file/;
use Test::Chado qw/chado_schema drop_schema/;
use Test::Chado::Common qw/:all/;
use Modware::DataSource::Chado::Organism;
use Modware::Spec::GFF3::Analysis;

{

    package MyChadoGFF3;
    use Moose;

    has 'schema' => ( is => 'rw', isa => 'DBIx::Class::Schema' );

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

subtest 'make staging compatible hash data structure of GFF3' => sub {
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
    lives_ok { $helper->initialize } 'should run initialize';
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
    is( $insert_hashref->{id}, 'auto-chr1',
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
            end    => 3312764,
            strand => 1
        },
        'should have the expected featureloc hashref'
    );
    drop_schema();
};
