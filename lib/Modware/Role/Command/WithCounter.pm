package Modware::Role::Command::WithCounter;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use MooseX::Role::Parameterized;

# Module implementation
#

parameter counter_for => (
    isa      => 'ArrayRef',
    required => 1
);

role {
    my $p = shift;
    for my $name ( @{ $p->counter_for } ) {
        has $name => (
            is      => 'rw',
            isa     => 'Num',
            default => 0,
            traits  => [qw/Counter NoGetopt/],
            handles => {
                'set_' . $name   => 'set',
                'incr_' . $name  => 'inc',
                'reset_' . $name => 'reset'
            }
        );
    }
};

1;    # Magic true value required at end of module

