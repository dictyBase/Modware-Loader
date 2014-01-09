package StagingGFF3Runner;
use FindBin qw/$Bin/;
use File::ShareDir qw/module_dir/;
use Modware::Loader;
use Test::Exception;
use Test::DatabaseRow;
use Test::Chado qw/:schema/;
use Test::Roo;
use SQL::Library;
use Bio::Chado::Schema;
use File::Spec::Functions;
use Log::Log4perl qw/:easy/;
use MooX::Types::MooseLike::Base qw/InstanceOf/;
use Modware::DataSource::Chado::Organism;

has 'loader'  => ( is => 'rw' );
has 'backend' => ( is => 'rw' );
has 'schema'  => (
    is      => 'lazy',
    default => sub {
        my ($self) = @_;
        my $schema = chado_schema( load_fixture => 1 );
        if ( $self->backend eq 'sqlite' ) {
            return Bio::Chado::Schema->connect( sub { $schema->storage->dbh }
            );
        }
        return $schema;
    }
);
has 'sqllib' => (
    is      => 'lazy',
    default => sub {
        my ($self) = @_;
        return SQL::Library->new(
            {   lib => catfile(
                    module_dir('Modware::Loader'),
                    $self->backend . '_gff3.lib'
                )
            }
        );
    }
);
has 'organism' => (
    is      => 'lazy',
    default => sub {
        return Modware::DataSource::Chado::Organism->new(
            genus   => 'Homo',
            species => 'sapiens'
        );
    }
);

has 'analysis_spec' => (
    is  => 'rw',
    isa => InstanceOf ['Modware::Spec::GFF3::Analysis']
);

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
    Test::Chado->ignore_tc_env(1) if $self->backend eq 'sqlite';
    $Test::DatabaseRow::dbh = $self->schema->storage->dbh;
    my $module
        = 'Modware::Loader::GFF3::Staging::' . ucfirst( $self->backend );
    require_ok $module;
    my $loader;
    lives_ok {
        $loader = $module->new(
            schema      => $self->schema,
            sqlmanager  => $self->sqllib,
            logger      => get_logger('MyStaging::Loader'),
            target_type => 'EST',
            organism    => $self->organism
        );
    }
    'should instantiate the loader';
    $loader->analysis_spec( $self->analysis_spec ) if $self->analysis_spec;
    $self->loader($loader);
};

after 'teardown' => sub {
    drop_schema();
};

test 'initialize' => sub {
    my ($self) = @_;
    lives_ok { $self->loader->initialize } 'should initialize';
    if ( $self->analysis_spec ) {
        like( $self->loader->analysis_id,
            qr/\d{1,}/, 'should have an analysis_id' );
        my $aspec = $self->analysis_spec;
        row_ok(
            sql => [
                "SELECT analysis_id FROM analysis WHERE program = ? AND name = ? AND programversion = ?",
                $aspec->program, $aspec->name, $aspec->programversion
            ],
            rows        => 1,
            description => 'should have analysis row'
        );
    }
};

1;

