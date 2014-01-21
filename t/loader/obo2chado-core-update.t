use Test::More qw/no_plan/;
use FindBin qw($Bin);
use Path::Class::Dir;
use Test::Exception;
use Test::Chado qw/:all/;
use Test::Chado::Common qw/:all/;
use Test::Chado::Cvterm qw/:all/;
use File::Temp qw/tmpnam/;
use Log::Log4perl;

my $data_dir    = Path::Class::Dir->new($Bin)->parent->subdir('test_data');
my $obo_fixture = $data_dir->subdir('preset')->file('cvprop.tar.bz2');

use_ok('Modware::Load');

subtest 'updating ontology' => sub {
    $Log::Log4perl::LOGEXIT_CODE = 1;
    my $schema    = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();
    my $loader    = new_ok('Modware::Load');
    local @ARGV = (
        'obo2chado',                                     '--dsn',
        $dbmanager->dsn,                                 '--user',
        $dbmanager->user,                                '--password',
        $dbmanager->password,                            '--input',
        $data_dir->subdir('obo')->file('eco_v2.00.obo'), 
    );
    push @ARGV, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');

    lives_ok { $loader->run } "should load eco obo file";
    drop_schema();
};

subtest 'updating cv terms and relationships from obo file' => sub {
    my $schema    = chado_schema( custom_fixture => $obo_fixture );
    my $dbmanager = get_dbmanager_instance();
    my $loader    = new_ok('Modware::Load');
    my @cmd       = (
        'obo2chado', '--dsn', $dbmanager->dsn, '--user',
        $dbmanager->user, '--password', $dbmanager->password
    );
    push @cmd, '--pg_schema', $dbmanager->schema_namespace
        if $dbmanager->can('schema_namespace');

    local @ARGV = ( @cmd, '--input',
        $data_dir->subdir('obo')->file('eco_v2.00.obo') );
    lives_ok { $loader->run } "should load eco_v2.00 obo file";

    count_cvterm_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 268 },
        'should have loaded 268 cvterms'
    );
    count_obsolete_cvterm_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 1 },
        'should have 1 obsolete cvterm'
    );

    is_obsolete_cvterm(
        $schema,
        { 'cv' => 'eco', 'term' => 'not_recorded (obsolete ECO:0000037)' },
        'not_recorded should be an obsolete cvterm'
    );

    count_object_ok(
        $schema,
        {   'cv'         => 'eco',
            'subject'    => 'protein BLAST evidence used in manual assertion',
            count        => 1,
            relationship => 'is_a'
        },
        'should have one is_a object'
    );

    my %relationships = (
        'ligand binding evidence'      => 'immunological assay evidence',
        'immunological assay evidence' => 'immunoprecipitation evidence',
        'immunological assay evidence' =>
            'enzyme-linked immunoabsorbent assay evidence'
    );
    has_relationship(
        $schema,
        {   'object'       => $_,
            'subject'      => $relationships{$_},
            'relationship' => 'is_a'
        },
        "should have the is_a relationship between $_ and $relationships{$_}"
    ) for keys %relationships;

    @ARGV = ( @cmd, '--input', $data_dir->subdir('obo')->file('eco.obo') );
    lives_ok { $loader->run } "should update ontology from eco.obo file";
    count_cvterm_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 294 },
        'should have loaded 268 cvterms after update'
    );
    count_obsolete_cvterm_ok(
        $schema,
        { 'cv' => 'eco', 'count' => 3 },
        'should have 3 obsolete cvterms after update'
    );
    has_dbxref( $schema, $_,
        "should have created new dbxref $_ after update" )
        for ( '0000325', '0000326', '0000327',
        '0000328', '0000329', '0000330' );
    has_cvterm( $schema, $_,
        "should have created new cvterm $_ after update" )
        for (
        'particle size and count assay evidence',
        'substance quantification evidence',
        'gel electrophoresis evidence',
        'plasmid maintenance assay evidence'
        );
    count_object_ok(
        $schema,
        {   'cv'         => 'eco',
            'subject'    => 'protein BLAST evidence used in manual assertion',
            count        => 2,
            relationship => 'is_a'
        },
        'should have two is_a objects after update'
    );

    %relationships = (
        'affinity evidence'      => 'immunological assay evidence',
        'protein assay evidence' => 'immunoprecipitation evidence',
        'protein assay evidence' =>
            'enzyme-linked immunoabsorbent assay evidence',
        'sequence similarity evidence' =>
            'sequence similarity evidence used in automatic assertion',
        'sequence similarity evidence used in automatic assertion' =>
            'motif similarity evidence used in automatic assertion',
        'sequence similarity evidence used in manual assertion' =>
            'sequence orthology evidence used in manual assertion',
        'experimental evidence'     => 'plasmid maintenance assay evidence',
        'biological assay evidence' => 'competitive growth assay evidence'
    );
    has_relationship(
        $schema,
        {   'object'       => $_,
            'subject'      => $relationships{$_},
            'relationship' => 'is_a'
        },
        "should have the is_a relationship between $_ and $relationships{$_} after update"
    ) for keys %relationships;

    is_obsolete_cvterm(
        $schema,
        {   'cv'   => 'eco',
            'term' => 'in vitro binding evidence (obsolete ECO:0000148)'
        },
        'in vitro binding evidence  should be an obsolete cvterm after update'
    );

    drop_schema();
};

