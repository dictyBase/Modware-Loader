package Modware::Import::Command::organism2chado;

use strict;
use feature qw/say/;
use namespace::autoclean;
use Moose;
use LWP::UserAgent;
use URI::Escape;
use Data::Dumper;
extends qw/Modware::Import::CommandPlus/;
with 'Modware::Role::Command::WithOutputLogger';
with 'Modware::Role::Command::WithBCS';
with 'MooseX::Object::Pluggable';

has 'plugin' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'Amoebozoa',
    documentation =>
        'Name of the plugin that process all children of given taxon, default Amoebozoa'
);

has 'taxon_id' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => '554915',
    documentation =>
        'All the species of this taxon id will be fetched and loaded in chado, default is 554915(Amoebozoa)'
);

has 'sparql_query' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $taxon_id = $self->taxon_id;
        my $query = <<"SPARQL";
PREFIX up_core:<http://purl.uniprot.org/core/> 
PREFIX taxon:<http://purl.uniprot.org/taxonomy/>
PREFIX rdfs:<http://www.w3.org/2000/01/rdf-schema#>
SELECT ?genus ?taxonId  ?species ?common_name ?strain 
WHERE
{

    ?taxonId a up_core:Taxon .
    ?taxonId rdfs:subClassOf+ taxon:$taxon_id .
    ?taxonId up_core:scientificName ?species .
    ?genusId up_core:rank up_core:Genus .
    ?taxonId rdfs:subClassOf+ ?genusId .
    ?genusId up_core:scientificName ?genus
    OPTIONAL {
            ?taxonId up_core:commonName ?common_name .
            ?taxonId up_core:strain ?strain_type .
            ?strain_type up_core:name ?strain .
            ?taxonId up_core:rank up_core:Species .
    }
} 
ORDER BY ASC(?species)
SPARQL
        return $query;
    },
    documentation =>
        'The sparql query, it is preferable not to change the default from command line'
);

has 'sparql_endpoint' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'http://beta.sparql.uniprot.org',
    documentation =>
        'The sparql endpoint, default is http://beta.sparql.uniprot.org'
);

has 'pg_schema' => (
    is      => 'rw',
    isa     => 'Str',
    trigger => sub {
        my ( $self, $name ) = @_;
        $self->add_connect_hook("SET SCHEMA '$name'");
    },
    documentation =>
        'Name of postgresql schema where the organism entries will be loaded, default is public, obviously ignored for other backend'
);

has 'plugin_namespace' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'Modware::Plugin::Import::Organism',
    documentation =>
        'Namespace of plugin module, default is Modware::Plugin::Import::Organism'
);

sub execute {
    my ($self) = @_;
    my $schema = $self->schema;
    my $logger = $self->output_logger;
    $logger->debug('running sparql query');
    my $url
        = $self->sparql_endpoint
        . '?query='
        . uri_escape( $self->sparql_query );
    my $res = LWP::UserAgent->new->get( $url,
        'Accept' => 'text/tab-separated-values' );
    if ( $res->is_error ) {
        $logger->logcroak( $res->code, "\t", $res->status_line );
    }
    $logger->debug("got sparql result");

    my $raw_str = $self->raw2str($res->decoded_content);
    #load plugin
    $self->load_plugin(
        '+' . $self->plugin_namespace . '::' . $self->plugin );
    
    my $bcs_str = $self->raw2db_structure($raw_str);
    $logger->debug(sprintf "going to load %d entries after db process", scalar @$bcs_str);
     #do everything under a single transaction
    my $guard = $schema->txn_scope_guard;
    $self->schema->resultset('Organism::Organism')->populate($bcs_str);
    $guard->commit;
}


sub raw2str {
    my ($self, $content) = @_;
    my @all_lines = split /\n/, $content;
    my $header = shift @all_lines;
    my $str;
    for my $line(@all_lines) {
        chomp $line;
        $line =~ s/\r//;
        my @data = split /\t/, $line;
        s/"//g for @data;
        my $hash =   {
            genus => $data[0],
            taxon => $data[1],
        };
        if ($data[2] =~ /^(\S+)\s(.+)$/ ) {
            $hash->{species} = $2;
        }
        $hash->{common_name} = $data[3] if $data[3];
        $hash->{strain} = $data[4] if $data[4];
        push @$str, $hash;
    }
    return $str;
}

1;

__END__

=head1 NAME

Modware::Import::Command::organism2chado - Retrieve organism entries from UniProt and load in chado database
