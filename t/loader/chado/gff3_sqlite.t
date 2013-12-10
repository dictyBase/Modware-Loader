use Test::More qw/no_plan/;
use Test::Exception;
use Test::Chado qw/:schema/;
use Test::DatabaseRow;
use FindBin qw/$Bin/;
use Path::Class::Dir;
use Bio::Chado::Schema;
use File::Spec::Functions;
use File::ShareDir qw/module_dir/;
use Modware::Loader;
use SQL::Library;
use Log::Log4perl qw/:easy/;
use Bio::GFF3::LowLevel qw/gff3_parse_feature gff3_parse_directive/;
use Bio::SeqIO;
use Modware::DataSource::Chado::Organism;
use Modware::Loader::GFF3::Staging::Sqlite;

Test::Chado->ignore_tc_env(1);    #make it sqlite specific

use_ok 'Modware::Loader::GFF3::Chado::Sqlite';

my $tmp_schema = chado_schema( load_fixture => 1 );
my $schema = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );
my $sqllib = SQL::Library->new(
    { lib => catfile( module_dir('Modware::Loader'), 'sqlite_gff3.lib' ) } );
Log::Log4perl->easy_init($ERROR);

my $staging_loader = Modware::Loader::GFF3::Staging::Sqlite->new(
    schema      => $schema,
    sqlmanager  => $sqllib,
    logger      => get_logger('MyStaging::Loader'),
    target_type => 'EST',
    organism    => Modware::DataSource::Chado::Organism->new(
        genus   => 'Homo',
        species => 'sapiens'
    )
);
$staging_loader->initialize;
$staging_loader->create_tables;
my $test_input
    = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
    ->subdir('gff3')->file('test1.gff3')->openr;

while ( my $line = $test_input->getline ) {
    if ( $line =~ /^#{2,}/ ) {
        my $hashref = gff3_parse_directive($line);
        if ( $hashref->{directive} eq 'FASTA' ) {
            my $seqio = Bio::SeqIO->new(
                -fh     => $test_input,
                -format => 'fasta'
            );
            while ( my $seq = $seqio->next_seq ) {
                $hashref->{seq_id}   = $seq->id;
                $hashref->{sequence} = $seq->seq;
                $staging_loader->add_data($hashref);
            }
        }
    }
    else {
        my $feature_hashref = gff3_parse_feature($line);
        $staging_loader->add_data($feature_hashref);
    }
}
$staging_loader->bulk_load;
# setup ends

my $loader = new_ok 'Modware::Loader::GFF3::Chado::Sqlite';
$loader->schema($schema);
$loader->logger( get_logger('MyChado::Logger') );
$loader->sqlmanager($sqllib);
my $return;
lives_ok { $return = $loader->bulk_load } 'should load in chado';
is_deeply(
    $return,
    {   temp_new_feature         => 50,
        new_feature              => 50,
        new_featureloc           => 48,
        new_featureloc_target    => 2,
        new_analysisfeature      => 6,
        new_feature_synonym      => 4,
        new_synonym              => 3,
        new_feature_relationship => 36,
        new_feature_dbxref       => 5,
        new_dbxref               => 5,
        new_featureprop          => 12,
    },
    'should match create hash'
);
my $test_sql = SQL::Library->new(
    {   lib => Path::Class::Dir->new($Bin)->parent->parent->subdir('test_sql')
            ->file('gff3_feature.lib')
    }
);
local $Test::DatabaseRow::dbh = $schema->storage->dbh;
row_ok(
    sql         => $test_sql->retr('feature_rows'),
    rows        => 50,
    description => 'should have 50 feature rows'
);
row_ok(
    sql         => [ $test_sql->retr('analysisfeature_rows'), $_ ],
    rows        => 1,
    description => "should have analysisfeature for id $_"
) for qw/match00002 match00003 c128.1 trans-1/;
row_ok(
    sql         => [ $test_sql->retr('feature_dbxref_rows'), $_ ],
    rows        => 1,
    description => "should have dbxref for id $_"
) for qw/tier0 trans-8 trans-1/;
row_ok(
    sql         => [ $test_sql->retr('feature_dbxref_rows'), 'thing2' ],
    rows        => 2,
    description => "should have multiple dbxrefs for id thing2"
);
row_ok(
    sql         => [ $test_sql->retr('parent_featurerel_rows'), $_ ],
    rows        => 1,
    description => "should have parent feature for id $_"
) for qw/utr1 utr2/;
row_ok(
    sql         => [ $test_sql->retr('parent_featurerel_rows'), $_ ],
    rows        => 2,
    description => "should have multiple parent features for id $_"
) for qw/child1 child2/;
row_ok(
    sql         => [ $test_sql->retr('feature_synonym_rows'), $_ ],
    rows        => 1,
    description => "should have  feature synonym for id $_"
) for qw/trans-2 trans-1/;
row_ok(
    sql         => [ $test_sql->retr('featureprop_rows'), $_ ],
    rows        => 1,
    description => "should have featureprop for id $_"
) for qw/trans-2 trans-1 tier0.1/;
row_ok(
    sql         => [ $test_sql->retr('featureproptype_rows'), $_, 'Gap' ],
    rows        => 1,
    description => "should have Gap featureprop for id $_"
) for qw/match00002 match00003/;
row_ok(
    sql         => [ $test_sql->retr('child_featureloc_rows'), 'Contig3' ],
    rows        => 7,
    description => "should have child featureloc for Contig3"
);
row_ok(
    sql         => [ $test_sql->retr('child_featureloc_rows'), 'Contig1' ],
    rows        => 33,
    description => "should have child featureloc for Contig1"
);
my $flocs = [
    [ 1000, 2000, 'trans-1' ],
    [ 5000, 6000, 'c128.1' ],
    [ 8000, 9000, 'c128.2' ],
    [ 1999, 3000, 'tier0' ],
    [ 2800, 2900, 'utr1' ],
    [ 2500, 2551, 'parent2' ]
];

for my $row (@$flocs) {
    row_ok(
        sql => [
            $test_sql->retr('feature_featureloc_rows'),
            $row->[2], 'Contig1', $row->[0], $row->[1], 0
        ],
        rows => 1,
        description =>
            "should have featureloc entry with reference Contig1 for feature $row->[2]"
    );
}

my $flocs2 = [
    [ 4,    506,  'match00002', 'EST_A',  1 ],
    [ 0,    502,  'match00003', 'EST_B',  1 ],
    [ 1199, 3200, 'match00002', 'ctg123', 0 ],
    [ 6999, 9000, 'match00003', 'ctg123', 0 ],
];

for my $row (@$flocs2) {
    row_ok(
        sql => [
            $test_sql->retr('feature_featureloc_rows'),
            $row->[2], $row->[3], $row->[0], $row->[1], $row->[4]
        ],
        rows => 1,
        description =>
            "should have featureloc entry with rank $row->[-1] to reference $row->[3] for feature $row->[2]"
    );
}
my %seqrow;
row_ok(
    sql => [$test_sql->retr('featureseq_row'), 'Contig1'],
    store_row => \%seqrow
);
is($seqrow{fseq}, 'ttctt', 'should match the first five nucleotides of Contig1 feature');
drop_schema();


