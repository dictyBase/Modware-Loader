
use Test::More qw/no_plan/;
use Test::Moose::More;
use Test::Chado qw/:all/;
use Test::Chado::Common qw/:all/;
use Test::Exception;
use Test::File;
use Path::Class::Dir;
use Log::Log4perl::Logger qw(:easy);
use Log::Log4perl::Level;
use File::Temp;
use FindBin qw($Bin);

my $schema   = chado_schema();
my $data_dir = Path::Class::Dir->new($Bin)->parent->subdir('test_data');
Log::Log4perl->easy_init(
    {   level => $INFO,
        file  => File::Temp->new()->filename
    }
);

use_ok('Modware::Import::Stock::PlasmidImporter');
my $importer = new_ok(Modware::Import::Stock::PlasmidImporter);
$importer->schema($schema);
$importer->logger( Log::Log4perl->get_logger('My::TestChado') );

can_ok( $importer, 'import_' . $_ ) for qw/stock props publications images/;

does_ok(
    $importer,
    'Modware::Role::Stock::Import::DataStash',
    'does the DataStash role'
);

my $props_input = $data_dir->file('plasmid_props.tsv');

# file_exists_ok($props_input);
dies_ok { $importer->import_props($props_input) }
'Should die as plasmid not loaded';

my $plasmid_input = $data_dir->file('plasmid_plasmid.tsv');

# file_exists_ok($strain_input);
lives_ok { $importer->import_stock($plasmid_input) }
'Should import plasmid data';
my $plasmid_rs = $schema->resultset('Stock::Stock')
    ->search( { 'type.name' => 'plasmid' }, { join => 'type' } );
is( $plasmid_rs->count, 50, 'Should have 50 plasmid entries' );

lives_ok { $importer->import_props($props_input) }
'Should load plasmid props';
my $plasmid_prop_rs
    = $schema->resultset('Stock::Stockprop')
    ->search( { 'type.name' => 'plasmid' },
    { join => { 'stock' => 'type' } } );
is( $plasmid_prop_rs->count, 85, 'Should have 85 stockprop entries' );

drop_schema();
