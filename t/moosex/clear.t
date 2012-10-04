use Test::More qw/no_plan/;
use Data::Dumper;

{
   package GoneAfter;
   use namespace::autoclean;
   use Moose;
   use Modware::MooseX::ClearAfterAccess;

   has 'stable' => ( is => 'rw',  isa => 'Str');
   has 'unstable' => (is => 'rw',  isa => 'Str',  traits => [qw/ClearAfterAccess/]);

   __PACKAGE__->meta->make_immutable;
   1;

}

my $ga = GoneAfter->new;
is($ga->$_, undef, "attribute $_ is undefined") for qw/stable unstable/;

$ga->stable('stay');
$ga->unstable('go');

is($ga->stable,  'stay',  'attribute stable gets the correct value');
is($ga->unstable,  'go',  'attribute unstable gets the correct value');

is($ga->stable,  'stay',  'attribute stable has the correct value after the access');
is($ga->unstable,  undef,   'attribute unstable is undefined after the access');

