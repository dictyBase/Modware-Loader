package ChadoGFF3Runner;
use Test::Roo;
use MooX::Types::MooseLike::Base qw/Str/;
use Test::Chado qw/:schema/;
use Bio::Chado::Schema;


has 'backend' => ( is => 'rw', isa => Str );
with 'ChadoGFF3';
with 'TestChadoGFF3';


sub BUILD {
    my ($self) = @_;
    if ( $self->backend eq 'postgresql' ) {
        plan
            skip_all => 'Environment variable TC_DSN is not set',
            if not defined $ENV{TC_DSN};
        eval { require DBD::Pg }
            or plan skip_all => 'DBD::Pg is needed to run this test';
    }
}

before 'setup' => sub {
    my ($self) = @_;
    if ( $self->backend eq 'sqlite' ) {
        Test::Chado->ignore_tc_env(1);    #make it sqlite specific

    }
    $self->setup_staging_loader;
    $self->setup_staging_env;
    $self->test_file('test1.gff3');
    $self->load_data_in_staging;
    $self->setup_chado_loader;
};

1;

