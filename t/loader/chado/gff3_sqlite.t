use Test::Roo;
use FindBin qw/$Bin/;
use File::Spec::Functions;
use lib catdir( $Bin, '..', '..', 'lib' );

has 'backend' => ( is => 'ro', default => 'sqlite' );
with 'ChadoGFF3';
with 'TestChadoGFF3';

before 'setup' => sub {
    my ($self) = @_;
    Test::Chado->ignore_tc_env(1);    #make it sqlite specific
    $self->setup_staging_loader;
    $self->setup_staging_env;
    $self->test_file('test1.gff3');
    $self->load_data_in_staging;
    $self->setup_chado_loader;
};

run_me;
done_testing;


