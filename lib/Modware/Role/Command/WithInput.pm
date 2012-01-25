package Modware::Role::Command::WithInput;

use strict;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Moose::Util::TypeConstraints;
use Path::Class::File;
use IO::Handle;

# Module implementation
#
subtype 'FileObject' => as class_type('Path::Class::File');
coerce 'FileObject' => from 'Str' => via { Path::Class::File->new($_) };

has 'output' => (
    is          => 'rw',
    isa         => 'FileObject',
    traits      => [qw/Getopt/],
    cmd_aliases => 'o',

    #required      => 1,
    coerce        => 1,
    predicate     => 'has_output',
    documentation => 'Name of the output file'
);

has 'output_handler' => (
    is      => 'ro',
    isa     => 'IO::Handle',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return $self->has_output
            ? $self->output->openw
            : IO::Handle->new_from_fd( fileno(STDOUT), 'w' );
    }
);

1;    # Magic true value required at end of module
