package TestChadoGFF3CmdLine;
use Test::DatabaseRow;
use Test::Roo::Role;

requires 'test_sql';
test 'analysis_count' => sub {
    my ($self) = @_;
SKIP: {
        skip "analysis_program is not set", 1 if !$self->analysis_program;
        row_ok(
            sql => [
                $self->test_sql->retr('analysis_count'),
                $self->analysis_program,
                $self->analysis_name,
                $self->analysis_program_version
            ],
            rows        => 5,
            description => 'should have 5 analysis under '
                . $self->analysis_program
        );
    }
};

test 'synonym_count' => sub {
    my ($self) = @_;
SKIP: {
        skip "synonym type is not set", 2 if !$self->synonym_type;
        row_ok(
            sql => [
                $self->test_sql->retr('synonym_type_count'),
                $self->synonym_type
            ],
            rows        => 2,
            description => 'should have synonyms with cvterm '
                . $self->synonym_type
        );
        row_ok(
            sql => [
                $self->test_sql->retr('feature_synonym_count'),
                'GFF3-loader',
            ],
            rows        => 3,
            description => 'should have feature_synonym rows with default pubplace'
        );

    }

};

1;
