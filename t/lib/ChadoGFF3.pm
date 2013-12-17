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
        target_type => 'EST',
        organism    => $self->organism
    );
    'should instantiate the loader';
    $self->staging_loader($loader);
}

sub setup_staging_env {
    my ($self) = @_;
    my $loader = $self->staging_loader;
    $staging_loader->initialize;
    $staging_loader->create_tables;
}

sub load_data_in_staging {
    my ($self)         = @_;
    my $input          = $self->input;
    my $staging_loader = $self->staging_loader;
    my $seqio;
    while ( my $line = $input->getline ) {
        if ( $line =~ /^#{2,}/ ) {
            my $hashref = gff3_parse_directive($line);
            if ( $hashref->{directive} eq 'FASTA' ) {
                $seqio = Bio::SeqIO->new(
                    -fh     => $test_input,
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


sub do_bulk_load {
    my ($self) = @_;
    my $loader = $self->loader;
    my $return;
    lives_ok { $return = $loader->bulk_load } 'should load in chado';
    is_deeply(
        $return,
        {   temp_new_feature         => 50,
            new_feature              => 50,
            new_featureloc           => 48,
            new_featureloc_target    => 2,
            new_analysisfeature      => 6,
            new_feature_synonym      => 4,
            new_synonym              => 3,
            new_feature_relationship => 36,
            new_feature_dbxref       => 5,
            new_dbxref               => 5,
            new_featureprop          => 12,
        },
        'should match create hash'
    );
};

has 'test_file' => ( is => 'rw', isa => Str );
has 'input' => (
    is      => 'lazy',
    default => sub {
        my ($self) = @_;
        my $file
            = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
            ->subdir('gff3')->file( $self->test_file )->openr;
        return $file;
        }

);

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
        return Path::Class::Dir->new($Bin)->parent->parent->subdir('test_sql')
            ->file('gff3_feature.lib');
    }
);


test 'bulk_load' => sub {
    my ($self) = @_;
    $self->do_bulk_load;
};

1;
