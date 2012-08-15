package Modware::Report::Command;


use namespace::autoclean;
use Moose;
extends qw/MooseX::App::Cmd::Command/;

with 'Modware::Role::Command::WithOutputLogger';


__PACKAGE__->meta->make_immutable;

1;

