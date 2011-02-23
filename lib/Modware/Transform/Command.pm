package Modware::Transform::Command;


# Other modules:
use Moose;
use YAML qw/LoadFile/;
extends qw/MooseX::App::Cmd::Command/;

# Module implementation
#
with 'MooseX::ConfigFromFile';

has '+configfile' => (
    cmd_aliases   => 'c',
    documentation => 'yaml config file to specify all command line options',
    traits        => [qw/Getopt/]
);


sub get_config_from_file {
    my ( $self, $file ) = @_;
    return LoadFile($file);
}


1;    # Magic true value required at end of module

