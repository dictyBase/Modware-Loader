
use strict;
use warnings;

use Test::More qw/no_plan/;
use Test::Moose;

BEGIN { require_ok('Modware::Load::Command::ebiGaf2dictyChado'); }

my $gafu = GAFUpdater->new();
isa_ok( $gafu, 'GAFUpdater' );

has_attribute_ok( $gafu, $_, "has $_ attribute" )
    for qw/ua ebi_base_url schema/;
can_ok( $gafu, $_ ) for qw/get_gene_ids query_ebi parse/;

isnt( $gafu->schema, 'Bio::Chado::Schema', '->schema not defined' );

my @gene_ids = qw/DDB_G0272616/;
my $gaf      = $gafu->query_ebi( $gene_ids[0] );
$gafu->parse($gaf);
my $annotation = Annotation->new;
isa_ok( $annotation, 'Annotation' );
has_attribute_ok( $annotation, $_, "has $_ attribute" )
    for
    qw/go_id qualifier with_from date evidence_code db gene_id gene_symbol/;
