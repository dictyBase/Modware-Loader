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

use_ok 'Modware::Loader::GFF3::Staging::Pg';
SKIP: {
    skip 'Environment variable TC_DSN is not set',
        if not defined $ENV{TC_DSN};
    eval { require DBD::Pg };
    skip 'DBD::Pg is needed to run this test' if $@;

    my $loader = new_ok 'Modware::Loader::GFF3::Staging::Pg';

    my $schema = chado_schema( load_fixture => 1 );
    my $sqllib = SQL::Library->new(
        { lib => catfile( module_dir('Modware::Loader'), 'pg_gff3.lib' ) } );
    Log::Log4perl->easy_init($ERROR);
    $loader->schema($schema);
    $loader->sqlmanager($sqllib);
    $loader->logger( get_logger('MyStaging::Loader') );
    $loader->target_type('EST');
    $loader->organism(
        Modware::DataSource::Chado::Organism->new(
            genus   => 'Homo',
            species => 'sapiens'
        )
    );
    local $Test::DatabaseRow::dbh = $schema->storage->dbh;

    my $test_input
        = Path::Class::Dir->new($Bin)->parent->parent->subdir('test_data')
        ->subdir('gff3')->file('test1.gff3')->openr;
    lives_ok { $loader->initialize } 'should initialize';
    lives_ok { $loader->create_tables } 'should create staging tables';
    row_ok(
        sql =>
            "SELECT table_name FROM information_schema.tables where table_type = 'LOCAL TEMPORARY'",
        results     => 10,
        description => 'should have created 10 staging tables'
    );
    lives_ok {

        while ( my $line = $test_input->getline ) {
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
                        $loader->add_data($hashref);
                    }
                }
            }
            else {
                my $feature_hashref = gff3_parse_feature($line);
                $loader->add_data($feature_hashref);
            }
        }
    }
    'should add_data';
    is( $loader->count_entries_in_feature_cache,
        50, 'should have 50 entries in feature cache' );
    is( $loader->count_entries_in_analysisfeature_cache,
        6, 'should have 6 entries in analysis feature cache' );
    is( $loader->count_entries_in_featureloc_cache,
        48, 'should have 48 entries in featureloc cache' );
    is( $loader->count_entries_in_feature_synonym_cache,
        4, 'should have 4 entries in feature synonym cache' );
    is( $loader->count_entries_in_feature_relationship_cache,
        36, 'should have 36 entries in feature relationship cache' );
    is( $loader->count_entries_in_feature_dbxref_cache,
        5, 'should have 5 entries in feature dbxref cache' );
    is( $loader->count_entries_in_featureprop_cache,
        12, 'should have 12 entries in featureprop cache' );
    is( $loader->count_entries_in_featureloc_target_cache,
        2, 'should have 2 entries in featureloc_target cache' );
    lives_ok { $loader->bulk_load } 'should bulk load';
    row_ok(
        sql => [
            "SELECT * from temp_feature where organism_id = ?",
            $loader->organism_id
        ],
        results     => 50,
        description => 'should have 50 feature entries'
    );
    row_ok(
        sql         => "SELECT * from temp_feature where id = 'trans-1'",
        results     => 1,
        description => 'should have id trans-1'
    );
    row_ok(
        sql         => "SELECT * from temp_feature where name = 'abc-1'",
        results     => 1,
        description => 'should have name abc-1'
    );
    row_ok(
        sql =>
            "SELECT * from temp_feature where name = '9th-gene' AND id = 'thing1'",
        results     => 1,
        description => 'should have name 9th-gene with id thing1'
    );
    row_ok(
        sql     => "SELECT * from temp_featureloc where seqid ='Contig4'",
        results => 4,
        description =>
            "should have 4 temp_featureloc entries with seqid Contig4"
    );
    row_ok(
        sql =>
            "SELECT * from temp_featureloc where seqid = 'Contig1' AND id = 'trans-1' AND start = 1000 AND stop = 2000 AND strand = 1",
        results     => 1,
        description => 'should have featureloc with id trans-1'
    );
    row_ok(
        sql =>
            "SELECT * from temp_analysisfeature where id = 'c128.1' AND score = 13.5",
        results     => 1,
        description => 'should have an analysis row for id c128.1'
    );
    row_ok(
        sql => [
            "SELECT * from temp_feature_synonym where id = 'trans-2' AND alias = 'xyz-2' AND type_id = ? and pub_id = ?",
            $loader->synonym_type_id,
            $loader->synonym_pub_id
        ],
        results     => 1,
        description => 'should have an alias for id trans-2'
    );
    row_ok(
        sql =>
            "SELECT * from temp_feature_relationship where id = 'parent2' and parent_id = 'gparent1'",
        results     => 1,
        description => 'should have parent id'
    );
    row_ok(
        sql => "SELECT * from temp_feature_relationship where id = 'child1'",
        results     => 2,
        description => 'should have two parents'
    );
    row_ok(
        sql =>
            "SELECT * from temp_feature_dbxref where id = 'trans-8' AND dbxref = 'PFD0755c' and db_id = (SELECT db_id from db where name = 'GeneDB_Pfalciparum')",
        results     => 1,
        description => 'should have dbxref for id trans-8'
    );
    row_ok(
        sql =>
            "SELECT * from temp_featureprop where id = 'trans-2' AND property LIKE 'Terribly%' AND type_id = (SELECT cvterm_id FROM cvterm where name = 'Note')",
        result      => 1,
        description => 'should have Note feature property'
    );
    row_ok(
        sql         => "SELECT seqlen from temp_featureseq",
        result      => 3,
        description => "should have three sequence entries"
    );
    row_ok(
        sql    => "SELECT seqlen from temp_featureseq where id = 'Contig4'",
        result => 1,
        description => "should have one sequence entry for Contig4"
    );

##testing for Target GFF3 features
    row_ok(
        sql =>
            "SELECT * from temp_feature where id = 'EST_A' and type_id = (SELECT cvterm_id from cvterm where name = 'EST')",
        result => 1,
        description =>
            "should have created a single EST entry from target feature"
    );

    row_ok(
        sql =>
            "SELECT * from temp_feature where id = 'match00002' and type_id = (SELECT cvterm_id from cvterm where name = 'match_part')",
        result => 1,
        description =>
            "should have created a match_part entry with id match00002"
    );
    row_ok(
        sql =>
            "SELECT * from temp_featureprop where id = 'match00002' and type_id = (SELECT cvterm_id FROM cvterm where name = 'Gap')",
        result      => 2,
        description => 'should have Gap feature properties for ctg123'
    );
    row_ok(
        sql =>
            "SELECT * from temp_featureloc_target where id = 'match00003' and rank = 1 and start = 0 and stop = 502 and strand = -1",
        result => 1,
        description =>
            'should have a featureloc entry for id match00003 on the query backend'
    );
    row_ok(
        sql =>
            "SELECT * from temp_featureloc where id = 'match00003' and start = 6999 and stop = 9000 and strand = 1 and seqid = 'ctg123'",
        result => 1,
        description =>
            'should have a featureloc entry for id match00003 on the reference backend'
    );
    drop_schema();
    $test_input->close;
}
