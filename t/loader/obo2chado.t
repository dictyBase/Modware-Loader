use Test::More qw/no_plan/;
use FindBin qw($Bin);
use Path::Class::Dir;
use Test::Exception;
use Test::Chado qw/:all/;
use Test::Chado::Common qw/:all/;
use Test::Chado::Cvterm qw/:all/;

my $data_dir    = Path::Class::Dir->new($Bin)->parent->subdir('test_data');
my $obo_fixture = $data_dir->subdir('preset')->file('cvprop.tar.bz2');

use_ok('Modware::Load');

subtest 'loading of obo file' => sub {
    my $schema    = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();
    my $loader    = new_ok('Modware::Load');
    local @ARGV = (
        'obo2chado',          '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->subdir('obo')->file('eco.obo'),
    );
    push @ARGV, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');

    lives_ok { $loader->run } "should load eco obo file";
    has_cv( $schema, 'eco', 'should have loaded eco ontology' );
    drop_schema();
};

subtest 'loading of cv terms and relationships from obo file' => sub {
    my $schema    = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();
    my $loader    = new_ok('Modware::Load');
    local @ARGV = (
        'obo2chado',          '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->subdir('obo')->file('eco.obo'),
    );
    push @ARGV, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');

    lives_ok { $loader->run } "should load eco obo file";
    my @names = (
        'experimental evidence',
        'immunofluorescence evidence',
        'affinity evidence',
        'structural similarity evidence',
        'phylogenetic evidence',
        'used_in'
    );
    has_cvterm( $schema, $_, "should have term $_" ) for @names;

    my @dbxrefs = qw(0000006 0000007 0000008 0000023 used_in);
    has_dbxref( $schema, $_, "should have dbxref $_" ) for @dbxrefs;
    count_cvterm_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 294 },
        'should have loaded 294 cvterms'
    );
    count_subject_ok(
        $schema,
        {   'cv'           => 'eco',
            'count'        => 14,
            object         => 'direct assay evidence',
            'relationship' => 'is_a'
        },
        'should have 14 subjects of term direct assay evidence'
    );
    count_subject_ok(
        $schema,
        {   'cv'           => 'eco',
            'count'        => 58,
            object         => 'manual assertion',
            'relationship' => 'used_in'
        },
        'should have 58 subjects of term manual assertion'
    );
    my $subject = 'non-traceable author statement used in manual assertion';
    count_object_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 3, 'subject' => $subject },
        "should have 3 objects of term $subject"
    );
    count_object_ok(
        $schema,
        {   'cv'         => 'eco',
            'count'      => 1,
            'subject'    => $subject,
            relationship => 'used_in'
        },
        "should have 1 object of term $subject with relationship used_in"
    );
    has_relationship(
        $schema,
        {   'subject'      => 'curator inference',
            'object'       => 'evidence',
            'relationship' => 'is_a'
        },
        "should have 1 is_a relationship between curator inference and evidence terms"
    );
    has_relationship(
        $schema,
        {   'subject' =>
                'genomic microarray evidence used in manual assertion',
            'object'       => 'manual assertion',
            'relationship' => 'used_in'
        },
        "should have a used_in relationship between genomic microarray evidence used in manual assertion and manual assertion terms"
    );
    drop_schema();
};

subtest 'loading of cvterms metadata from obo file' => sub {
    my $schema    = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();
    my $loader    = new_ok('Modware::Load');
    local @ARGV = (
        'obo2chado',          '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->subdir('obo')->file('eco.obo'),
    );
    push @ARGV, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');

    lives_ok { $loader->run } "should load eco obo file";
    count_synonym_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 213 },
        "should have 213 synonyms in eco ontology"
    );
    count_comment_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 68 },
        "should have 68 comments in eco ontology"
    );
    count_alt_id_ok(
        $schema,
        { 'count' => 7, 'db' => 'ECO' },
        "should have 7 alt ids in eco ontology"
    );
    has_synonym(
        $schema,
        {   'cv'      => 'eco',
            'term'    => 'similarity evidence',
            'synonym' => 'inferred from similarity'
        },
        "should have inferred from similarity synonym for similarity evidence term"
    );
    my $comment
        = 'Genomic cluster analyses include synteny and operon structure.';
    has_comment(
        $schema,
        {   'cv'      => 'eco',
            'term'    => 'gene neighbors evidence',
            'comment' => $comment
        },
        "should have $comment comment for term gene neighbors evidence"
    );
    has_alt_id(
        $schema,
        {   'cv'     => 'eco',
            'term'   => 'sequence orthology evidence',
            'alt_id' => 'ECO:00000060'
        },
        'should have ECO:00000060 as alt_id'
    );

    drop_schema();
};

subtest 'loading of ro obo file' => sub {
    my $schema    = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();
    my $loader    = new_ok('Modware::Load');
    local @ARGV = (
        'obo2chado',          '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->subdir('obo')->file('ro.obo'),
    );
    push @ARGV, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');

    lives_ok { $loader->run } "should load ro obo file";
    has_cv( $schema, 'ro', 'should have ro ontology' );
    for my $name (
        qw/has_part realized_in preceded_by has_participant function_of/)
    {
        has_cvterm( $schema, $name, "should have term $_" );
    }
    for my $dbxref (
        qw/0000050 0000060 0000080 results_in_development_of results_in_morphogenesis_of HOM0000073/
        )
    {
        has_dbxref( $schema, $dbxref, "should have dbxref $dbxref" );
    }
    count_subject_ok(
        $schema,
        {   cv           => 'ro',
            count        => 14,
            object       => 'overlaps',
            relationship => 'is_a'
        },
        'should have 14 subjects of term overlaps'
    );
    drop_schema();
};
