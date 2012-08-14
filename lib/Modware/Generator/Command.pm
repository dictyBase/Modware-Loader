package Modware::Generator::Command;


# Other modules:
use namespace::autoclean;
use Moose;
extends qw/MooseX::App::Cmd::Command/;

# Module implementation
#
with 'Modware::Role::Command::WithOutputLogger';

__PACKAGE__->meta->make_immutable;




1;    # Magic true value required at end of module

