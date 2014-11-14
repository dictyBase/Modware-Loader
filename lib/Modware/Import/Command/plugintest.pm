package Modware::Import::Command::plugintest;
use strict;
use namespace::autoclean;
use Moose;
extends qw/Modware::Import::CommandPlus/;
with 'MooseX::Object::Pluggable';

sub execute {
    my ($self) = @_;
    $self->load_plugin('load your plugin');
    # Now call the method
}

=head1 NAME

Modware::Import::Command::plugintest - A mock application to test runtime load of plugins.

1;
