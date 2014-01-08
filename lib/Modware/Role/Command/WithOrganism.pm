package Modware::Role::Command::WithOrganism;
use strict;
use namespace::autoclean;
use Moose::Role;
use Modware::DataSource::Chado::Organism;

requires qw/schema logger/;
has 'species' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Name of species, should exist in chado. It should be provided with genus'
);

has 'genus' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Name of the genus, should exist in chado. It should be provided with species'
);


has 'common_name' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Common name of the organism, should exist in chado, will only be used only if both species and genus are not provided',
);

has 'organism' => (
    isa         => 'Modware::DataSource::Chado::Organism',
    is          => 'ro',
    traits      => [qw/NoGetopt/],
    lazy => 1,
    builder => '_build_organism'
);

sub _build_organism {
    my ($self) = @_;
    my $organism = Modware::DataSource::Chado::Organism->new;
    for my $api(qw/species genus common_name/) {
        $organism->$api($self->$api) if $self->$api;
    }
    if (!$organism->exists_in_datastore($self->schema)) {
        $self->logger->error("given organism do not exist in database!!!");
        $self->logger->logdie("please create an entry before loading");
    }
    return $organism;
}


1;

__END__
