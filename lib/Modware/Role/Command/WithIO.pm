package Modware::Role::Command::WithIO;

use strict;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Cwd;
use File::Spec::Functions qw/catfile catdir rel2abs/;
use File::Basename;
use IO::Handle;
use Modware::Load::Types qw/DataDir DataFile FileObject/;

# Module implementation
#

has 'input' => (
    is            => 'rw',
    isa           => FileObject,
    traits        => [qw/Getopt/],
    cmd_aliases   => 'i',
    coerce        => 1,
    predicate     => 'has_input',
    documentation => 'Name of the input file, if absent reads from STDIN'
);

has 'output' => (
    is            => 'rw',
    isa           => FileObject,
    traits        => [qw/Getopt/],
    cmd_aliases   => 'o',
    coerce        => 1,
    predicate     => 'has_output',
    documentation => 'Name of the output file,  if absent writes to STDOUT'
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

sub _build_data_dir {
    return rel2abs(cwd);
}

1;    # Magic true value required at end of module



