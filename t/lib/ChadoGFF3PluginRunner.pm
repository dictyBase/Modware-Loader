package ChadoGFF3PluginRunner;
use Test::Roo;
use Test::Exception;
use MooX::Types::MooseLike::Base qw/Str ConsumerOf/;
use Test::Chado qw/:schema :manager/;
use Bio::Chado::Schema;
use Test::DatabaseRow;
use FindBin qw/$Bin/;
use Path::Class::Dir;
use feature qw/say/;
use SQL::Library;
with 'ChadoGFF3CmdLine';

has 'backend' => ( is => 'rw', isa => Str );
has 'schema' => (
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
has 'dbmanager' => (
    is      => 'rw',
    isa     => ConsumerOf ['Test::Chado::Role::HasDBManager'],
    trigger => sub {
        my ( $self, $manager ) = @_;
        for my $api (qw/user password dsn/) {
            $self->$api( $manager->$api ) if $manager->$api;
        }
    }
);

has 'test_sql' => (
    is      => 'lazy',
    default => sub {
        my $file = Path::Class::Dir->new($Bin)->parent->subdir('test_sql')
            ->file('gff3_feature.lib');
        return SQL::Library->new( { lib => $file } );
    }
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

after 'teardown' => sub { drop_schema() };
before 'setup' => sub {
    my ($self) = @_;
    if ( $self->backend eq 'sqlite' ) {
        Test::Chado->ignore_tc_env(1);    #make it sqlite specific

    }
    my $schema = $self->schema;
    $Test::DatabaseRow::dbh = $schema->storage->dbh;
    $self->dbmanager( get_dbmanager_instance() );
    require_ok 'Modware::Load';
};

test 'run_cmdline_app' => sub {
    my ($self) = @_;
    local @ARGV = (
        'gff3tochado', '--dsn',   $self->dsn,      '-u',
        $self->user,   '-p',      $self->password, '-i',
        $self->input,  '--genus', $self->genus,    '--species',
        $self->species, '--version_plugin', 1
    );
    if ( $self->dbmanager->can('schema_namespace') ) {
        push @ARGV, '--pg_schema', $self->dbmanager->schema_namespace;
    }
    for my $opt (
        qw/synonym_type target_type analysis_name analysis_program analysis_program_version/
        )
    {
        if ( $self->$opt ) {
            push @ARGV, '--' . $opt, $self->$opt;
        }
    }

    my $app = new_ok 'Modware::Load';
    lives_ok { $app->run } 'should run the gff3tochado subcommand with version plugin';
};

1;

#__END__
