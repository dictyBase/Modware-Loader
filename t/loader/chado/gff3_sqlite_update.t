use Test::More qw/no_plan/;
use Test::Exception;
use Test::Chado qw/:schema/;
use Test::DatabaseRow;
use FindBin qw/$Bin/;
use Path::Class::Dir;
use Bio::Chado::Schema;
use File::Spec::Functions;
use File::ShareDir qw/module_dir/;
use Modware::Loader;
use SQL::Library;
use Log::Log4perl qw/:easy/;
use Bio::GFF3::LowLevel qw/gff3_parse_feature gff3_parse_directive/;
use Bio::SeqIO;
use Modware::DataSource::Chado::Organism;
use Modware::Loader::GFF3::Staging::Sqlite;
use Modware::Loader::GFF3::Chado::Sqlite;

Test::Chado->ignore_tc_env(1);    #make it sqlite specific

my $tmp_schema = chado_schema( load_fixture => 1 );
my $schema = Bio::Chado::Schema->connect( sub { $tmp_schema->storage->dbh } );
my $sqllib = SQL::Library->new(
    { lib => catfile( module_dir('Modware::Loader'), 'sqlite_gff3.lib' ) } );
Log::Log4perl->easy_init($ERROR);
my $test_input
    = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
    ->subdir('gff3')->file('test1.gff3')->openr;

my $staging_loader = make_staging_loader( $schema, $sqllib );
$staging_loader->initialize;
$staging_loader->create_tables;
add_data_in_staging( $test_input, $staging_loader );
$staging_loader->bulk_load;

# setup ends

my $loader = make_chado_loader( $schema, $sqllib );
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

#make staging loader ready for another input
$staging_loader->clear_all_caches;
truncate_staging_tables( $schema->storage->dbh );
my $test_input2
    = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
    ->subdir('gff3')->file('test2.gff3')->openr;
add_data_in_staging( $test_input2, $staging_loader );
my $test_sql = SQL::Library->new(
    {   lib => Path::Class::Dir->new($Bin)->parent->parent->subdir('test_sql')
            ->file('gff3_feature.lib')
    }
);
$staging_loader->bulk_load;
my $updated;
lives_ok { $updated = $loader->bulk_load }
'should update and create GFF3 features in chado';
is_deeply(
    $updated,
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
drop_schema();

sub truncate_staging_tables {
    my $dbh = shift;
    my $all
        = $dbh->selectall_arrayref(
        "SELECT name FROM sqlite_temp_master where type = 'table' AND tbl_name like 'temp%'"
        );
    for my $row (@$all) {
        $dbh->do(qq{DELETE FROM $row->[0]});
    }
}

sub make_staging_loader {
    my ( $schema, $sqllib ) = @_;
    my $staging_loader = Modware::Loader::GFF3::Staging::Sqlite->new(
        schema      => $schema,
        sqlmanager  => $sqllib,
        logger      => get_logger('MyStaging::Loader'),
        target_type => 'EST',
        organism    => Modware::DataSource::Chado::Organism->new(
            genus   => 'Homo',
            species => 'sapiens'
        )
    );
    return $staging_loader;
}

sub make_chado_loader {
    my ( $schema, $sqllib ) = @_;
    my $loader = Modware::Loader::GFF3::Chado::Sqlite->new(
        schema     => $schema,
        logger     => get_logger('MyChado::Logger'),
        sqlmanager => $sqllib
    );
    return $loader;
}

sub add_data_in_staging {
    my ( $input, $staging_loader ) = @_;
    while ( my $line = $input->getline ) {
        if ( $line =~ /^#{2,}/ ) {
            my $hashref = gff3_parse_directive($line);
            if ( $hashref->{directive} eq 'FASTA' ) {
                my $seqio = Bio::SeqIO->new(
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
}
