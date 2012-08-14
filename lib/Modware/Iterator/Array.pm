package Modware::Iterator::Array;

# Other modules:
use namespace::autoclean;
use Moose;

# Module implementation
#

has '_stack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    lazy    => 1,
    default => sub { [] },
    handles => {
        'get_by_index' => 'get',
        'add'          => 'push',
        'members'      => 'elements',
        'member_count' => 'count', 
        'has_member' => 'count', 
        'sort_member' => 'sort_in_place'
    }
);

1;    # Magic true value required at end of module

__END__

=head1 NAME

<Modware::Iterator::Array> - [An array based iterator]
