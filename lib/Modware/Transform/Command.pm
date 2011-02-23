package Modware::Transform::Command;


# Other modules:
use namespace::autoclean;
use Moose;
use YAML qw/LoadFile/;
extends qw/MooseX::App::Cmd::Command/;

# Module implementation
#
with 'MooseX::ConfigFromFile';

has '+configfile' => (
    cmd_aliases   => 'c',
    traits        => [qw/Getopt/], 
    documentation => 'yaml config file to specify all command line options'
);

__PACKAGE__->meta->make_immutable;


sub get_config_from_file {
    my ( $self, $file ) = @_;
    return LoadFile($file);
}


1;    # Magic true value required at end of module

