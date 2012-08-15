package Modware::Role::Command::WithInput;

use strict;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use IO::Handle;
use Modware::Load::Types qw/FileObject/;

# Module implementation
#

has 'input' => (
    is          => 'rw',
    isa         => FileObject,
    traits      => [qw/Getopt/],
    cmd_aliases => 'i',
    coerce        => 1,
    predicate     => 'has_input',
    documentation => 'Name of the input file, if absent reads from STDIN'
);

has 'input_handler' => (
    is      => 'ro',
    isa     => 'IO::Handle',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return $self->has_input
            ? $self->input->openr
            : IO::Handle->new_from_fd( fileno(STDIN), 'r' );
    }
);

1;    # Magic true value required at end of module

