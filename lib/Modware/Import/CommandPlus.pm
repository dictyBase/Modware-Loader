
use strict;

package Modware::Import::CommandPlus;

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

1;

__END__

=head1 NAME

Modware::Import::Command - Base class for writing import command module

=head1 DESCRIPTION


=cut
