use Test::More qw/no_plan/;
use Test::Moose;

{

    package MyDataClass;
    use Moose;
    with 'Modware::Role::WithDataStash' => {
        create_stash_for    => [qw/term synonym/],
        create_kv_stash_for => [qw/term synonym/]
    };
    1;
}

my $class = new_ok 'MyDataClass';
has_attribute_ok( $class, $_, "should have $_ attribute" )
    for ( '_term_cache', '_term_kv_cache', '_synonym_cache',
    '_synonym_kv_cache' );

my @apis;
for my $name (qw/term synonym/) {
    for my $type (qw/get set has delete/) {
        push @apis, $type . '_' . $name . '_row';
    }
    for my $type (qw/add_to clean entries_in count_entries_in/) {
        push @apis, $type . '_' . $name . '_cache';
    }
}

can_ok( $class, @apis );
