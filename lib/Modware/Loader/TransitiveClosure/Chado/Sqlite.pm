package Modware::Loader::TransitiveClosure::Chado::Sqlite;
use namespace::autoclean;
use Moose;

has 'schema' => ( is => 'rw', isa => 'Bio::Chado::Schema');
has 'logger' =>
    ( is => 'rw', isa => 'Log::Log4perl::Logger');


sub bulk_load {

}

sub alter_tables {

}

sub reset_tables {

}


with 'Modware::Loader::Role::WithChado';
__PACKAGE__->meta->make_immutable;
1;
