package Modware::Load::Command::gbassembly2chado;

use strict;
use namespace::autoclean;
use Moose;
use File::Spec::Functions;
use File::Basename;
use Bio::Chado::Schema;
use Modware::Loader::Genome::GenBank::Assembly;
extends qw/Modware::Load::Chado/;

has 'prefix' => (
    is        => 'rw',
    isa       => 'Str',
    predicate => 'has_id_prefix',
    documentation =>
        'id prefix to use for generating feature identifiers,  default is the first letter of genus and first two letters of species name'
);

has 'source' => (
    is            => 'rw',
    isa           => 'Str',
    lazy          => 1,
    default       => 'genbank:nucleotide',
    documentation => 'source of genome,  default is *genbank*'
);

has 'dbsource' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'dictyBase',
    documentation =>
        'chado database source where the genome is getting loaded, default is dictyBase'
);

has 'reference_type' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'supercontig',
    documentation =>
        'SO(sequence ontology cvterm) type of the reference feature,  default is supercontig'
);

has 'link_publication' => (
    is        => 'rw',
    isa       => 'Str',
    predicate => 'link_to_publication',
    documentation =>
        'Link literature reference to the features,  needs a publication id'
);

sub execute {
    my ( $self, $input ) = @_;

## -- setting log
    my $logger = $self->logger;
    my $schema = $self->schema;

    $logger->logdie("no contig file given\n") if !$input;

## -- genome loader
    my $loader = Modware::Loader::Genome::GenBank::Assembly->new;
    $loader->logger($logger);
    $loader->schema( $self->schema );
    $loader->transform_schema;
    $loader->id_prefix( $self->prefix ) if $self->has_id_prefix;
    $loader->reference_type( $self->reference_type );
    $loader->input($input);

## -- loading in database inside one transaction
    my $guard = $schema->txn_scope_guard;

## -- sets up database sources
    $loader->mod_source( $self->dbsource );

    # - for gmod bulk loader compat
    # - sets the Genbank source as dbxref accession with GFF_source as db.
    $loader->chado_dbxref;

## -- assembly datasource with contig information
    $loader->load_assembly;

## -- if given link literature to feature
    $loader->linkfeat2pub( $self->link_publication )
        if $self->link_to_publication;

    $guard->commit;
}

1;

=head1 NAME

Modware::Load::Command::gbassembly2chado -  Load genome assembly from genbank to oracle chado database
    
=head1 SYNOPSIS

perl modware-load gbassembly2chado [options] <genbank file>

perl modware-load gbassembly2chado -p PPA -dsn "dbi:Oracle:sid=modbase" -u tucker -pass halo genome_assembly.gb

perl modware-load gbassembly2chado  -p PPA -dsn "dbi:Oracle:sid=modbase" -u tucker -pass halo contig.gb
    

=head1 REQUIRED ARGUMENTS


-u,--user       chado database user name

--password,-pass       chado database password 


=head1 OPTIONS

--prefix                    id prefix to use for feature identifiers 

--source               source of genome,  default is genbank  

--dbsource             chado database source where the genome is getting loaded,  default is
                      dictyBase

--reference_type       type of reference feature(cvterm) for the scaffold,  default is
                      supercontig

--link_publication   Link literature reference to the features,  needs a publiction id for
                     linking


=head1 DESCRIPTION

Populates chado database with genomic assembly features from genbank file. The genbank
file expected to contain the contig assembly of the high level assembled feature such as
supercontigs and/or chromosomes. The top level features has to be loaded in database.


=head1 TODO

=over

=item Where to store the value of B<strain> tag

=item Storing the ncbi taxon_id coming from db_xref tag

=back


=head2 Moduralize oracle specific features

=over

=item Getting the next feature id

=item Setting up database table transformation in BCS schema

=back

