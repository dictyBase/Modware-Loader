package Modware::Factory::Chado::BCS;

use warnings;
use strict;

# Other modules:
use Module::Find;
use Carp;
use Class::MOP;
use Try::Tiny;
use List::MoreUtils qw/firstval/;

# Module implementation
#
sub new {
    my ( $class, %arg ) = @_;
    my $engine = $arg{engine} ? ucfirst lc( $arg{engine} ) : 'Generic';
    my $package = firstval {/$engine$/}
        findsubmod('Modware::DataSource::Chado::BCS::Engine');
    croak "cannot find plugins for engine: $engine\n" if !$package;
    try {
        Class::MOP::load_class($package);
    }
    catch {
        croak "Issue in loading $package $_\n";
    };
    return $package->new(%arg);
}

1;    # Magic true value required at end of module

__END__

