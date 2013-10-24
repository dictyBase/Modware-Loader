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
use Modware::Loader::TransitiveClosure::Staging::Postgresql;

use_ok 'Modware::Loader::TransitiveClosure::Chado::Postgresql';
use_ok('Modware::Load');

SKIP: {
    skip 'Environment variable TC_DSN is not set',
        if not defined $ENV{TC_DSN};
    eval { require DBD::Pg };
    skip 'DBD::Pg is needed to run this test' if $@;

    Log::Log4perl->easy_init($ERROR);

    subtest 'transitive closure' => sub {
        my ( $schema, $dbmanager, $sqlmanager, $staging_loader,
            $chado_loader );
        my $data_dir = Path::Class::Dir->new($Bin)
            ->parent->parent->subdir('test_data');
        my $setup = sub {
            my $preset = module_file( 'Test::Chado', 'cvpreset.tar.bz2' );
            $schema = chado_schema( custom_fixture => $preset );
            $dbmanager = get_dbmanager_instance();
            local @ARGV = (
                'obo2chado',
                '--dsn',
                $dbmanager->dsn,
                '--user',
                $dbmanager->user,
                '--password',
                $dbmanager->password,
                '--input',
                $data_dir->subdir('obo')->file('eco_v2.00.obo'),
                '--pg_schema',
                $dbmanager->schema_namespace
            );
            my $obo_loader = new_ok('Modware::Load');
            $obo_loader->run;
            $sqlmanager = SQL::Library->new(
                {   lib => module_file(
                        'Modware::Loader', 'postgresql_transitive.lib'
                    )
                }
            );
            $staging_loader
                = Modware::Loader::TransitiveClosure::Staging::Postgresql->new(
                schema     => $schema,
                sqlmanager => $sqlmanager,
                namespace  => 'eco',
                logger     => get_logger('MyStaging::Loader')
                );
            my $test_handler
                = $data_dir->subdir('obo_closure')->file('eco_v2.00.inf')
                ->openr;

            $staging_loader->create_tables;
            while ( my $row = $test_handler->getline() ) {
                $staging_loader->add_data($row);
            }
            $staging_loader->bulk_load;

        };

        my $teardown = sub {
            $staging_loader->drop_tables;
            $staging_loader->clean_cvtermpath_cache;
        };

        my $update_setup = sub {
            local @ARGV = (
                'obo2chado',          '--dsn',
                $dbmanager->dsn,      '--user',
                $dbmanager->user,     '--password',
                $dbmanager->password, '--input',
                $data_dir->subdir('obo')->file('eco.obo'),
                '--pg_schema',
                $dbmanager->schema_namespace

            );
            my $obo_loader = new_ok('Modware::Load');
            $obo_loader->run;
            my $test_handler
                = $data_dir->subdir('obo_closure')->file('eco.inf')->openr;
            $staging_loader->create_tables;
            while ( my $row = $test_handler->getline() ) {
                $staging_loader->add_data($row);
            }
            $staging_loader->bulk_load;
        };

        my $final_teardown = sub {
            drop_schema();
            $schema->storage->disconnect;
        };

        subtest 'loading in chado database with pg backend' => sub {
            $setup->();
            $chado_loader
                = new_ok 'Modware::Loader::TransitiveClosure::Chado::Postgresql';
            $chado_loader->sqlmanager($sqlmanager);
            $chado_loader->schema($schema);
            $chado_loader->logger( get_logger('MyChado::Loader') );

            lives_ok { $chado_loader->bulk_load } 'should load';
            is( $schema->resultset('Cv::Cvtermpath')->count( {} ),
                1233, 'should have 1233 entries in cvtermpath table' );
            $teardown->();
        };

        subtest => 'updating in chado database' => sub {
            $update_setup->();
            lives_ok { $chado_loader->bulk_load } 'should update';
            is( $schema->resultset('Cv::Cvtermpath')->count( {} ),
                1525,
                'should have updated to 1525 entries in cvtermpath table' );
            $final_teardown->();
        };
    };
}
