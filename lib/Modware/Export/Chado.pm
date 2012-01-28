package Modware::Export::Chado;

use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use YAML qw/LoadFile/;
extends qw/MooseX::App::Cmd::Command/;
with 'MooseX::ConfigFromFile';
with 'Modware::Role::Command::WithInput';
with 'Modware::Role::Command::WithBCS';
with 'Modware::Role::Command::WithReportLogger';

# Module implementation
#
has 'species' =>
    ( is => 'rw', isa => 'Str', documentation => 'Name of species' );
has 'genus' =>
    ( is => 'rw', isa => 'Str', documentation => 'Name of the genus' );


has 'organism' => (
    isa         => 'Str',
    is          => 'rw',
    traits      => [qw/Getopt/],
    cmd_aliases => 'org',
    documentation =>
        'Common name of the organism whose genomic features will be exported'
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

sub read_organism {
    my ( $self, $schema, $genus, $species, $organism ) = @_;
    my $query;
    $query->{species}     = $species  if $species;
    $query->{genus}       = $genus    if $genus;
    $query->{common_name} = $organism if $organism;

    my $org_rs = $schema->resultset('Organism::Organism')->search(
        $query,
        {   select => [
                qw/species genus
                    common_name organism_id/
            ]
        }
    );

    if ( $org_rs->count > 1 ) {
        my $msg =
            "you have more than one organism being selected with the current query\n";
        $msg .= sprintf( "Genus:%s\tSpecies:%s\tCommon name:%s\n",
            $_->genus, $_->species, $_->common_name )
            for $org_rs->all;
        $msg .=
            "Restrict your query to one organism: perhaps provide only **genus** and **species** for uniqueness";
        $self->logger->log_fatal($msg);
    }

    my $dbrow = $org_rs->first;
    if ( !$dbrow ) {
        $self->logger->log_fatal("Could not find given organism  in chado database");
    }
    return $dbrow;
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



__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module


