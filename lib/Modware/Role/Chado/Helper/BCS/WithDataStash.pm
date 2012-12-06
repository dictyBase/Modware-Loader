package Modware::Role::Chado::Helper::BCS::WithDataStash;

# Other modules:
use namespace::autoclean;
use MooseX::Role::Parameterized;

# Module implementation
#

parameter create_stash_for => ( isa => 'ArrayRef[Str]' );

role {
    my $p = shift;
    return if not defined $p->create_stash_for;
    for my $name ( @{ $p->create_stash_for } ) {
        has '_'
            . $name
            . '_cache' => (
            is      => 'rw',
            isa     => 'ArrayRef',
            traits  => [qw/Array/],
            handles => {
                'add_to_' . $name . '_cache'           => 'push',
                'clean_' . $name . '_cache'            => 'clean',
                'entries_in_' . $name . '_cache'       => 'elements',
                'count_entries_in_' . $name . '_cache' => 'count'
            },
            lazy    => 1,
            default => sub { [] },
            );

    }

};

1;    # Magic true value required at end of module

__END__

=head1 NAME

<Modware::Role::Chado::Helper::WithDataStash> - [Role for generating perl datastructures
to be consumed with BCS's populate method]


=head1 SYNOPSIS

with Modware::Role::Chado::Helper::WithDataStash => 
       { create_stash_for => [qw/cvterm relationship/] };



