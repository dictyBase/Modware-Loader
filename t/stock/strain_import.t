
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

use_ok('Modware::Import::Stock::StrainImporter');
my $importer = new_ok(Modware::Import::Stock::StrainImporter);
$importer->schema($schema);
$importer->logger( Log::Log4perl->get_logger('My::TestChado') );

can_ok( $importer, 'import_' . $_ ) for qw/stock props/;

does_ok(
    $importer,
    'Modware::Role::Stock::Import::DataStash',
    'does the DataStash role'
);

my $props_input = $data_dir->file('strain_props.tsv');

# file_exists_ok($props_input);
dies_ok { $importer->import_props($props_input) }
'Should die as strain not loaded';

my $strain_input = $data_dir->file('strain_strain.tsv');

# file_exists_ok($strain_input);
lives_ok { $importer->import_stock($strain_input) }
'Should import strain data';
my $strain_rs = $schema->resultset('Stock::Stock')
    ->search( { 'type.name' => 'strain' }, { join => 'type' } );
is( $strain_rs->count, 50, 'Should have 50 strain entries' );

lives_ok { $importer->import_props($props_input) } 'Should load strain props';
my $strain_prop_rs
    = $schema->resultset('Stock::Stockprop')
    ->search( { 'type.name' => 'strain' },
    { join => { 'stock' => 'type' } } );
is( $strain_prop_rs->count, 85, 'Should have 85 stockprop entries' );

my $plasmid_input = $data_dir->file('strain_plasmid.tsv');
dies_ok { $importer->import_plasmid($plasmid_input) }
'Should die as plasmid not loaded, even though strain is loaded';

drop_schema();
