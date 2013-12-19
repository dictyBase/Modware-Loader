package TestChadoGFF3;
use Test::DatabaseRow;
use Test::Roo::Role;

test 'check_feature' => sub {
    my ($self) = @_;
    row_ok(
        sql         => $self->test_sql->retr('feature_rows'),
        rows        => 50,
        description => 'should have 50 feature rows'
    );
};
test 'feature_links' => sub {
    my ($self) = @_;
    my $test_sql = $self->test_sql;
    row_ok(
        sql         => [ $test_sql->retr('analysisfeature_rows'), $_ ],
        rows        => 1,
        description => "should have analysisfeature for id $_"
    ) for qw/match00002 match00003 c128.1 trans-1/;
    row_ok(
        sql         => [ $test_sql->retr('feature_dbxref_rows'), $_ ],
        rows        => 1,
        description => "should have dbxref for id $_"
    ) for qw/tier0 trans-8 trans-1/;
    row_ok(
        sql         => [ $test_sql->retr('feature_dbxref_rows'), 'thing2' ],
        rows        => 2,
        description => "should have multiple dbxrefs for id thing2"
    );
    row_ok(
        sql         => [ $test_sql->retr('feature_synonym_rows'), $_ ],
        rows        => 1,
        description => "should have  feature synonym for id $_"
    ) for qw/trans-2 trans-1/;
    row_ok(
        sql         => [ $test_sql->retr('featureprop_rows'), $_ ],
        rows        => 1,
        description => "should have featureprop for id $_"
    ) for qw/trans-2 trans-1 tier0.1/;
    row_ok(
        sql         => [ $test_sql->retr('featureproptype_rows'), $_, 'Gap' ],
        rows        => 1,
        description => "should have Gap featureprop for id $_"
    ) for qw/match00002 match00003/;
};

test 'feature_relationships' => sub {
    my ($self) = @_;
    my $test_sql = $self->test_sql;
    row_ok(
        sql         => [ $test_sql->retr('parent_featurerel_rows'), $_ ],
        rows        => 1,
        description => "should have parent feature for id $_"
    ) for qw/utr1 utr2/;
    row_ok(
        sql         => [ $test_sql->retr('parent_featurerel_rows'), $_ ],
        rows        => 2,
        description => "should have multiple parent features for id $_"
    ) for qw/child1 child2/;
    row_ok(
        sql  => [ $test_sql->retr('child_featureloc_rows'), 'Contig3' ],
        rows => 7,
        description => "should have child featureloc for Contig3"
    );
    row_ok(
        sql  => [ $test_sql->retr('child_featureloc_rows'), 'Contig1' ],
        rows => 33,
        description => "should have child featureloc for Contig1"
    );
};

test 'feature_locations' => sub {
    my ($self)   = @_;
    my $test_sql = $self->test_sql;
    my $flocs    = [
        [ 1000, 2000, 'trans-1' ],
        [ 5000, 6000, 'c128.1' ],
        [ 8000, 9000, 'c128.2' ],
        [ 1999, 3000, 'tier0' ],
        [ 2800, 2900, 'utr1' ],
        [ 2500, 2551, 'parent2' ]
    ];

    for my $row (@$flocs) {
        row_ok(
            sql => [
                $test_sql->retr('feature_featureloc_rows'),
                $row->[2], 'Contig1', $row->[0], $row->[1], 0
            ],
            rows => 1,
            description =>
                "should have featureloc entry with reference Contig1 for feature $row->[2]"
        );
    }

    my $flocs2 = [
        [ 4,    506,  'match00002', 'EST_A',  1 ],
        [ 0,    502,  'match00003', 'EST_B',  1 ],
        [ 1199, 3200, 'match00002', 'ctg123', 0 ],
        [ 6999, 9000, 'match00003', 'ctg123', 0 ],
    ];

    for my $row (@$flocs2) {
        row_ok(
            sql => [
                $test_sql->retr('feature_featureloc_rows'),
                $row->[2], $row->[3], $row->[0], $row->[1], $row->[4]
            ],
            rows => 1,
            description =>
                "should have featureloc entry with rank $row->[-1] to reference $row->[3] for feature $row->[2]"
        );
    }
};

test 'featureseq' => sub {
    my ($self) = @_;
    my %seqrow;
    row_ok(
        sql       => [ $self->test_sql->retr('featureseq_row'), 'Contig1' ],
        store_row => \%seqrow
    );
    is( $seqrow{fseq}, 'ttctt',
        'should match the first five nucleotides of Contig1 feature' );
};

1;

