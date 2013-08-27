use Test::More qw/no_plan/;
use Test::Chado;
use Test::Chado::Common;
use FindBin qw($Bin);
use Path::Class::Dir;
use Test::Exception;

my $data_dir = Path::Class::Dir->new($Bin)->parent->subdir('test_data');

use_ok('Modware::Load');

subtest 'loading of obo files' => sub {
    my $schema
        = chado_schema(
        custom_fixture => $data_dir->subdir('preset')->file('cvprop.tar.bz2')
        );
    my $dbmanager = Test::Chado->fixture_loader_instance->dbmanager;
    my $loader    = new_ok('Modware::Load');
    local @ARGV = (
        'obo2chado',          '--dsn',
        $dbmanager->dsn,      '--user',
        $dbmanager->user,     '--password',
        $dbmanager->password, '--input',
        $data_dir->subdir('obo')->file('eco.obo')
    );

    lives_ok { $loader->run } "should load obo file";
    has_cv( $schema, 'eco', 'should have loaded eco ontology' );

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
    drop_schema();
};
