package ChadoGFF3UpdateRunner;
use Test::Roo;
use MooX::Types::MooseLike::Base qw/Str/;
use Test::Chado qw/:schema/;
use Bio::Chado::Schema;

has 'backend' => ( is => 'rw', isa => Str );
with 'ChadoGFF3';


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
    $self->test_file('test1.gff3');
    $self->setup_staging_loader;
    $self->setup_staging_env;
    $self->load_data_in_staging;
    $self->setup_chado_loader;
};

after 'do_bulk_load' => sub {
    my ($self) = @_;
    $self->staging_loader->clear_all_caches;
    my $api = 'truncate_'.$self->backend.'_staging_tables';
    $self->$api;
    $self->test_file('test2.gff3');
    $self->load_data_in_staging;
    $self->setup_chado_loader;
    $self->updated_bulk_load;
};

1;
