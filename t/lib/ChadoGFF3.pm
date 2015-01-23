package ChadoGFF3;
use Module::Load;
use FindBin qw/$Bin/;
use Test::Exception;
use Test::DatabaseRow;
use Test::Roo::Role;
use Test::Chado qw/:schema/;
use File::ShareDir qw/module_dir/;
use Modware::Loader;
use Path::Class::Dir;
use SQL::Library;
use Bio::Chado::Schema;
use Bio::GFF3::LowLevel qw/gff3_parse_feature gff3_parse_directive/;
use Bio::SeqIO;
use File::Spec::Functions;
use Log::Log4perl qw/:easy/;
use feature qw/say/;
use MooX::Types::MooseLike::Base qw/Str/;
use Modware::DataSource::Chado::Organism;

requires 'backend';

after 'teardown' => sub { drop_schema() };

sub setup_staging_loader {
    my ($self) = @_;
    $Test::DatabaseRow::dbh = $self->schema->storage->dbh;
    my $module
        = 'Modware::Loader::GFF3::Staging::' . ucfirst( $self->backend );
    load $module;
    my $loader;
    $loader = $module->new(
        schema      => $self->schema,
        sqlmanager  => $self->sqllib,
        logger      => get_logger('MyStaging::Loader'),
        organism    => $self->organism
    );
    $self->staging_loader($loader);
}

sub setup_staging_env {
    my ($self) = @_;
    my $loader = $self->staging_loader;
    $loader->initialize;
    $loader->create_tables;
}

sub load_data_in_staging {
    my ($self) = @_;
    my $input
        = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
        ->subdir('gff3')->file( $self->test_file )->openr;
    my $staging_loader = $self->staging_loader;
    my $seqio;
    while ( my $line = $input->getline ) {
        if ( $line =~ /^#{2,}/ ) {
            my $hashref = gff3_parse_directive($line);
            if ( $hashref->{directive} eq 'FASTA' ) {
                $seqio = Bio::SeqIO->new(
                    -fh     => $input,
                    -format => 'fasta'
                );
                while ( my $seq = $seqio->next_seq ) {
                    $hashref->{seq_id}   = $seq->id;
                    $hashref->{sequence} = $seq->seq;
                    $staging_loader->add_data($hashref);
                }
            }
        }
        else {
            my $feature_hashref = gff3_parse_feature($line);
            $staging_loader->add_data($feature_hashref);
        }
    }
    $staging_loader->bulk_load;
}

sub setup_chado_loader {
    my ($self) = @_;
    my $module = 'Modware::Loader::GFF3::Chado::' . ucfirst( $self->backend );
    require_ok $module;
    my $loader;
    lives_ok {
        $loader = $module->new(
            schema     => $self->schema,
            sqlmanager => $self->sqllib,
            logger     => get_logger('MyChado::Loader'),
        );
    }
    'should instantiate the loader';
    $self->loader($loader);
}

sub truncate_sqlite_staging_tables {
    my ($self) = @_;
    my $dbh = $self->schema->storage->dbh;
    my $all
        = $dbh->selectall_arrayref(
        "SELECT name FROM sqlite_temp_master where type = 'table' AND tbl_name like 'temp%'"
        );
    for my $row (@$all) {
        $dbh->do(qq{DELETE FROM $row->[0]});
    }
}

sub truncate_postgresql_staging_tables {
    my ($self) = @_;
    my $dbh = $self->schema->storage->dbh;
        my $all
        = $dbh->selectall_arrayref(
            "SELECT table_name FROM information_schema.tables where table_type = 'LOCAL TEMPORARY'",
        );
    for my $row (@$all) {
        $dbh->do(qq{TRUNCATE ONLY $row->[0]});
    }
}

sub do_bulk_load {
    my ($self) = @_;
    my $loader = $self->loader;
    my $return;
    lives_ok { $return = $loader->bulk_load } 'should load in chado';
    is_deeply(
        $return,
        {   temp_new_feature         => 53,
            new_feature              => 53,
            new_featureloc           => 51,
            new_featureloc_target    => 2,
            new_analysisfeature      => 6,
            new_feature_synonym      => 4,
            new_synonym              => 3,
            new_feature_relationship => 39,
            new_feature_dbxref       => 5,
            new_dbxref               => 5,
            new_featureprop          => 12,
        },
        'should match create hash'
    );
}

sub updated_bulk_load {
    my ($self) = @_;
    my $loader = $self->loader;
    my $return;
    lives_ok { $return = $loader->bulk_load } 'should load in chado';
    is_deeply(
        $return,
        {   temp_new_feature         => 21,
            new_feature              => 21,
            new_featureloc           => 21,
            new_featureloc_target    => 0,
            new_analysisfeature      => 0,
            new_feature_synonym      => 0,
            new_synonym              => 0,
            new_feature_relationship => 19,
            new_feature_dbxref       => 0,
            new_dbxref               => 0,
            new_featureprop          => 10,
        },
        'should match updated hash'
    );
}

has 'test_file' => ( is => 'rw', isa => Str );
has 'staging_loader' => ( is => 'rw' );
has 'loader'         => ( is => 'rw' );
has 'schema'         => (
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

has 'test_sql' => (
    is      => 'lazy',
    default => sub {
        my $file
            = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_sql')
            ->file('gff3_feature.lib');
        return SQL::Library->new( { lib => $file } );
    }
);

test 'bulk_load' => sub {
    my ($self) = @_;
    $self->do_bulk_load;
};

1;
