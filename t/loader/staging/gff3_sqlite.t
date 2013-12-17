use Test::DatabaseRow;
use Test::Roo;
use Test::Chado;
use FindBin qw/$Bin/;
use File::Spec::Functions;
use lib catdir( $Bin, '..', '..', 'lib' );

has 'backend' => ( is => 'ro', default => 'sqlite' );
with 'TestStagingGFF3';

before 'setup' => sub {
    my ($self) = @_;
    Test::Chado->ignore_tc_env(1);    #make it sqlite specific
    $self->setup_staging_loader;
};

test 'staging_tables' => sub {
    row_ok(
        sql =>
            "SELECT name FROM sqlite_temp_master where type = 'table' AND tbl_name like 'temp%'",
        results     => 10,
        description => 'should have created 9 staging tables'
    );
};
run_me;
done_testing;

