package Modware::Export::CommandPlus;

use strict;

use Moose;
use namespace::autoclean;
use YAML qw/LoadFile/;
extends qw/MooseX::App::Cmd::Command/;
with 'MooseX::ConfigFromFile';


has '+configfile' => (
    cmd_aliases   => 'c',
    documentation => 'yaml config file to specify all command line options',
    traits        => [qw/Getopt/], 
    default => sub {return undef}
);

sub get_config_from_file {
    my ( $self, $file ) = @_;
    return LoadFile($file);
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

<Modware::Export::CommandPlus> - [Another lightweight base class for writing export command module]

