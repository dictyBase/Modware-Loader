use Test::More qw/no_plan/;
use Test::Exception;
use Test::Chado qw/:schema :manager/;
use FindBin qw/$Bin/;
use Path::Class::Dir;
use IO::File;
use Bio::Chado::Schema;
use File::Spec::Functions;
use File::ShareDir qw/module_dir module_file/;
use Modware::Loader;
use SQL::Library;
use Log::Log4perl qw/:easy/;
use Modware::Loader::TransitiveClosure::Staging::Sqlite;

Test::Chado->ignore_tc_env(1);    #make it sqlite specific

use_ok 'Modware::Loader::TransitiveClosure::Chado::Sqlite';
use_ok('Modware::Load');
Log::Log4perl->easy_init($ERROR);

subtest 'loading transitive closure of eco ontology' => sub {
    my ( $schema, $sqlmanager, $staging_loader );
    my $setup = sub {
        my $preset = module_file( 'Test::Chado', 'eco.tar.bz2' );
        my $tmp_schema = chado_schema( custom_fixture => $preset );
        $schema
            = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh }
            );
        $sqlmanager = SQL::Library->new(
            {   lib =>
                    module_file( 'Modware::Loader', 'sqlite_transitive.lib' )
            }
        );
        $staging_loader
            = Modware::Loader::TransitiveClosure::Staging::Sqlite->new(
            schema     => $schema,
            sqlmanager => $sqlmanager,
            namespace  => 'eco',
            logger     => get_logger('MyStaging::Loader')
            );
        my $test_handler
            = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
            ->subdir('obo_closure')->file('eco.inf')->openr;

        $staging_loader->create_tables;
        while ( my $row = $test_handler->getline() ) {
            $staging_loader->add_data($row);
        }
        $staging_loader->bulk_load;
    };
    my $teardown = sub {
        drop_schema();
        $schema->storage->disconnect;
    };

    $setup->();
    my $chado_loader
        = new_ok 'Modware::Loader::TransitiveClosure::Chado::Sqlite';
    $chado_loader->sqlmanager($sqlmanager);
    $chado_loader->schema($schema);
    $chado_loader->logger( get_logger('MyChado::Loader') );

    lives_ok { $chado_loader->bulk_load } 'should load';
    is( $schema->resultset('Cv::Cvtermpath')->count( {} ),
        1525, 'should have 1525 entries in cvtermpath table' );
    $teardown->();
};

