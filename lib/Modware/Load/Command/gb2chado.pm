package Modware::Load::Command::gb2chado;
use strict;
use namespace::autoclean;
use Moose;
use File::Spec::Functions;
use File::Basename;
use Bio::Chado::Schema;
use Modware::Loader::Genome::GenBank;
extends qw/Modware::Load::Chado/;

has 'prefix' => (
    is  => 'rw',
    isa => 'Str',
    predicate => 'has_prefix', 
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

has 'genome_tag' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
    lazy    => 1,
    documentation =>
        'Flag to add a tag in chado organism_prop table to indicate the loaded genome,  default is true'
);

has 'link_publication' => (
    is        => 'rw',
    isa       => 'Str',
    predicate => 'link_to_publication', 
    documentation =>
        'Link literature reference to the features,  needs a publication id'
);

has 'feat2link' => (
    is         => 'rw',
    isa        => 'ArrayRef',
    auto_deref => 1,
    documentation =>
        'List of space separated features for linking to literature only if publication id  is provided. By default,  all available features are linked'
);

sub execute {
    my ($self) = @_;

## -- setting log
    my $logger
        = $self->logger;
    $logger->logdie("no input genbank file is given") if !$self->input_handler->opened;

## -- genome loader
    my $loader = Modware::Loader::Genome::GenBank->new;
    $loader->logger($logger);
    $loader->schema($self->schema);
    $loader->transform_schema;

    $loader->id_prefix($self->prefix) if $self->has_prefix;
    $loader->reference_type($self->reference_type);
    $loader->input( $self->input_handler );

## -- loading in database inside one transaction
    my $guard = $self->schema->txn_scope_guard;

## -- sets up database sources
    $loader->mod_source($self->dbsource);

    # - for gmod bulk loader compat
    # - sets the Genbank source as dbxref accession with GFF_source as db.
    $loader->chado_dbxref;

## -- load scaffolds and associated features
    $loader->load_scaffold;

## -- tag the genome being loaded
    $loader->add_genome_tag if $self->genome_tag;

## -- link literature to feature if any
    if ($self->link_to_publication) {
        $loader->add_feat2link($_) for $self->feat2link;
        $loader->linkfeat2pub($self->link_publication);
    }
    $guard->commit;
}

1;

=head1 NAME

Modware::Load::Command::gb2chado -  Populate oracle chado database from genbank file
    
=head1 SYNOPSIS

perl modware-load gb2chado [options] <genbank file>

perl modware-load gb2chado [ -u | --user[=username] ] [ -p | --pass | --password[=password] ]
	 [ --attr|--attribute [key=value] --attr|--attribute [key=value] ]
     [ --dsn[=DBI dsn string ] ] [--prefix[=idprefix] ] [ --source[=genome source] ]
     [ --dbsource[=database source] ] [ --reference_type[=reference feature] ]
     [ --log_file[=file] ] [ --[no]genome_tag ] [ --link_publication[=id] ]
     [ --[no]genome_tag ] [ --feat2link[=feat1] --feat2link[=feat2] ] 
     < genbank file >

perl gb2chado.pl -dsn "dbi:Oracle:sid=modbase" -u tucker -pass halo organism.gb

perl gb2chado.pl  -dsn "dbi:Oracle:sid=modbase" -u tucker -password halo  -p PPA ppalidum.gb

perl gb2chado.pl  -dsn "dbi:Oracle:sid=modbase" -u tucker -password halo  -p PPA \ 
     -link_publication 23456 ppalidum.gb
    

=head1 REQUIRED ARGUMENTS


-u,--user              chado database user name

-password,--pass       chado database password 

-dsn                   Database DBI dsn

<genbank file>         Genbank file


=head1 OPTIONS


-p                    id prefix to use for feature identifiers,  default is first letter
                      genus and the first two letters species. 

-source               source of genome,  default is genbank  

-dbsource             chado database source where the genome is getting loaded,  default is
                      dictyBase

-reference_type       type of reference feature(cvterm) for the scaffold,  default is
                      supercontig

-log_file             log to a file instead of STDERR,  default is STDERR

-genome_tag           Flag to add a tag in organism property table to indicate the loaded
                      genome,  default is true. 

-nogenome_tag        To negate the B<-genome_tag> option

-link_publication    Link literature reference to the features,  needs a publiction id for
                     linking

-feat2link           List of space separated features for linking the to the literature,
by default all features get linked.


=head1 DESCRIPTION

Populate genome from genbank file into chado database.

=head2 Loader specifications

=over

=item *

For every reference feature(supercontig/scaffold/chromosome etc...),  additional sequence
location metadata is added as feature property. For nuclear DNA sequence
I<nuclear_sequence> and for mitochondrial I<mitochondrial_DNA> cvterms are used from SO.
The information is parsed itself from the given genbank file.

=back


=head1 TODO

=over

=item Where to store the value of B<strain> tag

=item Storing the ncbi taxon_id coming from db_xref tag


=back


=head2 Moduralize oracle specific features

=over

=item Getting the next feature id

=item Setting up database table transformation in BCS schema

=item DBI connection attribute

=back


    

