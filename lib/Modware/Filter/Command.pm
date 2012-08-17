package Modware::Filter::Command;


use namespace::autoclean;
use Moose;
extends qw/MooseX::App::Cmd::Command/;
with 'Modware::Role::Command::WithOutputLogger';
with 'Modware::Role::Command::WithIO';


__PACKAGE__->meta->make_immutable;

1;

