use Test::More qw/no_plan/;
use FindBin qw($Bin);
use Path::Class::Dir;
use Test::Exception;
use Test::Chado qw/:all/;
use Test::Chado::Common qw/:all/;
use Test::Chado::Cvterm qw/:all/;
use File::Spec::Functions;

my $data_dir    = Path::Class::Dir->new($Bin)->parent->subdir('test_data');
my $obo_fixture = $data_dir->subdir('preset')->file('cvprop.tar.bz2');

use_ok('Modware::Load');

subtest 'updating metadata from obo file' => sub {
    my $schema = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();

    my $loader = new_ok('Modware::Load');
    my @cmd    = (
        'obo2chado', '--dsn', $dbmanager->dsn, '--user',
        $dbmanager->user, '--password', $dbmanager->password
    );
    push @cmd, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');
    local @ARGV = ( @cmd, '--input',
        $data_dir->subdir('obo')->file('eco_v2.00.obo') );

    lives_ok { $loader->run } "should load eco_v2.00 obo file";
    count_synonym_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 207 },
        "should have 207 synonyms"
    );
    count_comment_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 49 },
        "should have 49 comments"
    );
    has_synonym(
        $schema,
        {   'cv'      => 'eco',
            'term'    => 'automatic assertion',
            'synonym' => 'IEA'
        },
        "should have IEA synonym for automatic assertion term"
    );
    has_synonym(
        $schema,
        {   'cv'      => 'eco',
            'term'    => 'automatic assertion',
            'synonym' => 'inferred from electronic annotation'
        },
        "should have inferred from electronic annotation synonym for automatic assertion term"
    );
    has_synonym(
        $schema,
        {   'cv'      => 'eco',
            'term'    => 'expression pattern evidence',
            'synonym' => 'IEP'
        },
        "should have IEP synonym for expression pattern evidence"
    );
    count_alt_id_ok(
        $schema,
        { 'count' => 7, 'db' => 'ECO' },
        "should have 7 alt ids in eco ontology"
    );

    @ARGV = ( @cmd, '--input', $data_dir->subdir('obo')->file('eco.obo') );
    lives_ok { $loader->run } "should update ontology from eco.obo file";
    count_synonym_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 213 },
        "should have 213 synonyms after update"
    );
    count_comment_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 68 },
        "should have 68 comments after udpate"
    );
    has_synonym(
        $schema,
        {   'cv'      => 'eco',
            'term'    => 'enzyme-linked immunoabsorbent assay evidence',
            'synonym' => 'ELISA evidence'
        },
        "should have ELISA evidence synonym after update"
    );
    has_synonym(
        $schema,
        {   'cv'      => 'eco',
            'term'    => 'affinity evidence',
            'synonym' => 'ligand binding evidence'
        },
        "should have ligand binding evidence synonym after update"
    );
    has_comment(
        $schema,
        {   'cv'   => 'eco',
            'term' => 'structural similarity evidence',
            'comment' =>
                "For GO annotation, in the case of a single gene, an accession for the related gene's sequence is entered in the evidence_with field."
        },
        "should have a new comment for structural similarity evidence term after update"
    );
    count_alt_id_ok(
        $schema,
        { 'count' => 7, 'db' => 'ECO' },
        "should have 7 alt ids after update"
    );
    drop_schema();
};

subtest 'updating alt_id metadata from obo file' => sub {
    my $schema = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();

    my $loader = new_ok('Modware::Load');
    my @cmd    = (
        'obo2chado', '--dsn', $dbmanager->dsn, '--user',
        $dbmanager->user, '--password', $dbmanager->password
    );
    push @cmd, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');
    local @ARGV = (
        @cmd, '--input',
        $data_dir->subdir('obo')->file('dicty_phenotypes1.198.obo')
    );
    lives_ok { $loader->run } "should load dicty phenotypes ontology";
    count_synonym_ok(
        $schema,
        { 'cv' => 'dphen', 'count' => 318 },
        "should have 318 synonyms in Dictyostelium phenotypes ontology"
    );
    count_alt_id_ok(
        $schema,
        { 'count' => 59, 'db' => 'DDPHENO' },
        "should have 59 alt_ids in Dictyostelium phenotypes ontology"
    );

    @ARGV = (
        @cmd, '--input',
        $data_dir->subdir('obo')->file('dicty_phenotypes.obo')
    );
    lives_ok { $loader->run } "should update new phenotypes ontology";
    count_synonym_ok(
        $schema,
        { 'cv' => 'dphen', 'count' => 364 },
        "should have 364 synonyms after update"
    );
    count_alt_id_ok(
        $schema,
        { 'count' => 63, 'db' => 'DDPHENO' },
        "should have 63 alt ids after update"
    );
    drop_schema();
};

