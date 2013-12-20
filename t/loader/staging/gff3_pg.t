use Test::DatabaseRow;
use Test::Roo;
use FindBin qw/$Bin/;
use Log::Log4perl qw/:easy/;
use File::Spec::Functions;
use Modware::DataSource::Chado::Organism;
use lib catdir( $Bin, '..', '..', 'lib' );


has 'backend' => ( is => 'ro', default => 'postgresql' );
with 'TestStagingGFF3';

sub BUILD {
    my ($self) = @_;
    plan
        skip_all => 'Environment variable TC_DSN is not set',
        if not defined $ENV{TC_DSN};
    eval { require DBD::Pg }
        or plan skip_all => 'DBD::Pg is needed to run this test';
}

before 'setup' => sub {
    my ($self) = @_;
    $self->setup_staging_loader;
};
test 'staging_tables' => sub {
    row_ok(
        sql =>
            "SELECT table_name FROM information_schema.tables where table_type = 'LOCAL TEMPORARY'",
        results     => 10,
        description => 'should have created 10 staging tables'
    );
};
run_me;
done_testing;

