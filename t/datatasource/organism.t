use Test::More qw/no_plan/;
use Test::Chado qw/:schema :manager/;
use Test::Exception;
use Test::Moose;
use Bio::Chado::Schema;

use_ok 'Modware::DataSource::Chado::Organism';
subtest 'various arguments for exists_in_datastore' => sub {
    my $schema     = normalize_schema( chado_schema() );
    my $datasource = new_ok 'Modware::DataSource::Chado::Organism';
    does_ok( $datasource, 'Modware::Role::WithOrganism' );
    dies_ok { $datasource->exists_in_datastore }
    'should not run without schema argument';
    dies_ok { $datasource->exists_in_datastore($schema) }
    'should not run without organism metadata';
    drop_schema();
};

subtest 'existence of organism in datastore' => sub {
    my $schema = normalize_schema( chado_schema() );
    create_organism_fixture($schema);
    my $datasource
        = Modware::DataSource::Chado::Organism->new( common_name => 'dicty' );
    dies_ok { $datasource->exists_in_datastore($schema) }
    'should not run with existence of non unique entries';
    $datasource = Modware::DataSource::Chado::Organism->new(
        species => 'sapiens',
        genus   => 'Homo'
    );
    ok( $datasource->exists_in_datastore($schema),
        'should have Homo sapiens in datastore' );
    $datasource
        = Modware::DataSource::Chado::Organism->new( common_name => 'mouse' );
    ok( $datasource->exists_in_datastore($schema),
         'should have mouse in datastore' );
    drop_schema();
};

sub normalize_schema {
    my $schema = shift;
    if ( $schema->storage->sqlt_type eq 'SQLite' ) {
        return Bio::Chado::Schema->connect( sub { $schema->storage->dbh } );
    }
    return $schema;
}

sub create_organism_fixture {
    my ($schema) = shift;
    $schema->resultset('Organism::Organism')->populate(
        [   [qw/genus species common_name/],
            [qw/Homo sapiens human/],
            [qw/Mus musculus mouse/],
            [qw/Dictyostelium discoideum dicty/],
            [qw/Dictyostelium purpureum dicty/]
        ]
    );
}
