package Modware::Role::WithDataStash;

# Other modules:
use namespace::autoclean;
use MooseX::Role::Parameterized;

# Module implementation
#

parameter create_stash_for    => ( isa => 'ArrayRef[Str]' );
parameter create_kv_stash_for => ( isa => 'ArrayRef[Str]' );

role {
    my $p = shift;

    if ( defined $p->create_stash_for ) {
        for my $name ( @{ $p->create_stash_for } ) {
            has '_'
                . $name
                . '_cache' => (
                is      => 'rw',
                isa     => 'ArrayRef',
                traits  => [qw/Array/],
                handles => {
                    'add_to_' . $name . '_cache'           => 'push',
                    'clean_' . $name . '_cache'            => 'clear',
                    'entries_in_' . $name . '_cache'       => 'elements',
                    'get_entry_from_' . $name . '_cache'   => 'get',
                    'count_entries_in_' . $name . '_cache' => 'count'
                },
                lazy    => 1,
                default => sub { [] },
                );

        }
    }

    if ( defined $p->create_kv_stash_for ) {

        for my $name ( @{ $p->create_kv_stash_for } ) {
            my $api_hash;
            if ( length($name) > 2 ) {
                $api_hash = {
                    'get_' . $name . '_row'    => 'get',
                    'set_' . $name . '_row'    => 'set',
                    'has_' . $name . '_row'    => 'defined',
                    'delete_' . $name . '_row' => 'delete'
                };
            }
            else {
                $api_hash = {
                    'get_' . $name . 'row'    => 'get',
                    'set_' . $name . 'row'    => 'set',
                    'has_' . $name . 'row'    => 'defined',
                    'delete_' . $name . 'row' => 'delete'
                };
            }
            has '_'
                . $name
                . '_kv_cache' => (
                is      => 'rw',
                isa     => 'HashRef',
                traits  => [qw/Hash/],
                handles => $api_hash,
                lazy    => 1,
                default => sub { {} }
                );
        }
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






