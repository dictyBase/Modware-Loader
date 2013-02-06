
use Test::Moose;
use Test::Spec;

BEGIN { require_ok('Modware::Loader::GAF'); }

describe 'A GAF loader instance' => sub {
    my $loader;
    before all => sub {
        $loader = Modware::Loader::GAF->new;
    };
    it 'should have attributes' => sub {
        has_attribute_ok( $loader, $_ ) for qw/gaf limit manager/;
    };
    it 'should have methods' => sub {
        can_ok( $loader, $_ ) for qw/upsert load_gaf get_rank set_input/;
    };

    # TODO - Test for get_rank()
    # TODO - Test for upsert()
};
runtests unless caller;
