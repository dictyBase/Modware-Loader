package Modware::Export::Chado;

use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use YAML qw/LoadFile/;
extends qw/MooseX::App::Cmd::Command/;
with 'MooseX::ConfigFromFile';
with 'Modware::Role::Command::WithIO';
with 'Modware::Role::Command::WithBCS';
with 'Modware::Role::Command::WithReportLogger';

# Module implementation
#

has '_organism_result' => (
    is  => 'rw',
    isa => 'DBIx::Class::Row'
);

has 'species' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Name of species',
    predicate     => 'has_species'
);

has 'genus' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'Name of the genus',
    predicate     => 'has_genus'
);

has 'organism' => (
    isa         => 'Str',
    is          => 'rw',
    traits      => [qw/Getopt/],
    cmd_aliases => 'org',
    documentation =>
        'Common name of the organism whose genomic features will be exported',
    predicate => 'has_organism'
);

has '+configfile' => (
    cmd_aliases   => 'c',
    documentation => 'yaml config file to specify all command line options',
    traits        => [qw/Getopt/]
);

sub get_config_from_file {
    my ( $self, $file ) = @_;
    return LoadFile($file);
}

sub _chado_feature_id {
    my ( $self, $dbrow ) = @_;
    if ( my $dbxref = $dbrow->dbxref ) {
        if ( my $id = $dbxref->accession ) {
            return $id;
        }
    }
    else {
        return $dbrow->uniquename;
    }
}

sub _chado_name {
    my ( $self, $dbrow ) = @_;
    if ( my $name = $dbrow->name ) {
        return $name;
    }
}

sub gff_source {
    my ( $self, $dbrow ) = @_;
    my $dbxref_rs
        = $dbrow->search_related( 'feature_dbxrefs', {} )->search_related(
        'dbxref',
        { 'db.name' => 'GFF_source' },
        { join      => 'db' }
        );
    if ( my $row = $dbxref_rs->first ) {
        return $row->accession;
    }
}

sub _children_dbrows {
    my ( $self, $parent_row, $relation, $type ) = @_;
    $type = { -like => $type } if $type =~ /^%/;
    return $parent_row->search_related(
        'feature_relationship_objects',
        { 'type.name' => $relation },
        { join        => 'type' }
        )->search_related(
        'subject',
        { 'type_2.name' => $type },
        { join          => 'type' }
        );
}

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;

    if ( !$self->has_species ) {
        if ( !$self->has_genus ) {
            if ( !$self->has_organism ) {
                $logger->log_fatal(
                    "at least species,  genus or common_name has to be set");
            }
        }
    }

    my $query;
    $query->{species}     = $self->species  if $self->has_species;
    $query->{genus}       = $self->genus    if $self->has_genus;
    $query->{common_name} = $self->organism if $self->has_organism;

    my $org_rs = $self->schema->resultset('Organism::Organism')->search(
        $query,
        {   select => [
                qw/species genus
                    common_name organism_id/
            ]
        }
    );

    if ( $org_rs->count > 1 ) {
        my $msg
            = "you have more than one organism being selected with the current query\n";
        $msg .= sprintf( "Genus:%s\tSpecies:%s\tCommon name:%s\n",
            $_->genus, $_->species, $_->common_name )
            for $org_rs->all;
        $msg
            .= "Restrict your query to one organism: perhaps provide only **genus** and **species** for uniqueness";
        $logger->log_fatal($msg);
    }

    my $dbrow = $org_rs->first;
    if ( !$dbrow ) {
        $logger->log_fatal(
            "Could not find given organism  in chado database");
    }
    $self->_organism_result($dbrow);
    inner();
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

