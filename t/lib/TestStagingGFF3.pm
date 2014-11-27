package TestStagingGFF3;
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
use Modware::DataSource::Chado::Organism;

requires 'backend';

sub setup_staging_loader {
    my ($self) = @_;
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
    $self->loader($loader);
}

after 'teardown' => sub {
    my ($self) = @_;
    $self->input->close;
    drop_schema();
};

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
has 'loader' => ( is => 'rw' );
has 'test_file' => ( is => 'lazy', default => 'test1.gff3' );

test 'initialize' => sub {
    my ($self) = @_;
    lives_ok { $self->loader->initialize } 'should initialize';
    lives_ok { $self->loader->create_tables } 'should create staging tables';
};

test 'add_data' => sub {
    my ($self)     = @_;
    my $test_input = $self->input;
    my $loader     = $self->loader;
    my $seqio;
    lives_ok {
        while ( my $line = $test_input->getline ) {
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
};

test 'count_cache' => sub {
    my ($self) = @_;
    my $loader = $self->loader;
    is( $loader->count_entries_in_feature_cache,
        53, 'should have 53 entries in feature cache' );
    is( $loader->count_entries_in_analysisfeature_cache,
        6, 'should have 6 entries in analysis feature cache' );
    is( $loader->count_entries_in_featureloc_cache,
        51, 'should have 51 entries in featureloc cache' );
    is( $loader->count_entries_in_feature_synonym_cache,
        4, 'should have 4 entries in feature synonym cache' );
    is( $loader->count_entries_in_feature_relationship_cache,
        39, 'should have 39 entries in feature relationship cache' );
    is( $loader->count_entries_in_feature_dbxref_cache,
        5, 'should have 5 entries in feature dbxref cache' );
    is( $loader->count_entries_in_featureprop_cache,
        12, 'should have 12 entries in featureprop cache' );
    is( $loader->count_entries_in_featureloc_target_cache,
        2, 'should have 2 entries in featureloc_target cache' );
};

test 'bulk_load' => sub {
    my ($self) = @_;
    lives_ok { $self->loader->bulk_load } 'should bulk load';
};

test 'check_feature' => sub {
    my ($self) = @_;
    row_ok(
        sql => [
            "SELECT * from temp_feature where organism_id = ?",
            $self->loader->organism_id
        ],
        results     => 53,
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

    #check the polypeptide features
    for my $id (qw/poly-1 poly-2 poly-8/) {
        row_ok(
            sql         => [ "SELECT * from temp_feature where id = ?", $id ],
            results     => 1,
            description => "should have id $id"
        );
    }
};

test 'check_feature_links1' => sub {
    my ($self) = @_;
    my $loader = $self->loader;
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
            "SELECT * from temp_featureloc where seqid = 'Contig3' AND strand = 1 AND start = 32100 AND stop = 34900 AND id = 'poly-8'",
        results     => 1,
        description => 'should have featureloc with id poly-8'
    );
};

test 'feature_links2' => sub {
    my ($self) = @_;
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

    my $sql = <<'SQL';
    SELECT * FROM temp_feature_relationship where id = ? 
    AND parent_id = ?
    AND type_id = (SELECT cvterm_id FROM cvterm 
    JOIN cv ON cv.cv_id = cvterm.cv_id
    where cvterm.name = 'derives_from'
    AND cv.name = 'sequence'
    );
SQL

    my @rel;
    push @rel, [qw/poly-1 trans-1/], [qw/poly-2 trans-2/], [qw/poly-8 trans-8/];
    for my $frel(@rel) {
        row_ok(
            sql => [$sql, $frel->[0], $frel->[1]],
            result => 1,
            description => "should have parent $frel->[0] of child $frel->[1]"
        );
    }
};

###testing for Target GFF3 features
test 'featureloc_target' => sub {
    my ($self) = @_;
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
            'should have a featureloc entryfor id match00003 on the query backend'
    );
    row_ok(
        sql =>
            "SELECT * from temp_featureloc where id = 'match00003' and start = 6999 and stop = 9000 and strand = 1 and seqid = 'ctg123'",
        result => 1,
        description =>
            'should have a featureloc entry for id match00003 on the reference backend'
    );
};
1;
