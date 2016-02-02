package Modware::Import::Command::bibtex2chado;

use strict;
use feature qw/say/;
use namespace::autoclean;
use Moose;
use BibTeX::Parser;
use autodie qw/open close/;
extends qw/Modware::Import::CommandPlus/;
with 'Modware::Role::Command::WithOutputLogger';
with 'Modware::Role::Command::WithIO';
with 'Modware::Role::Command::WithBCS';
with 'MooseX::Object::Pluggable';

has '+output' => ( traits   => [qw/NoGetopt/] );
has '+input'  => ( required => 1 );

has 'plugin' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'BibTeX',
    documentation =>
        'Name of the plugin that will parse uniquename from bibtex file, default is BibTeX'
);

has 'pg_schema' => (
    is      => 'rw',
    isa     => 'Str',
    trigger => sub {
        my ( $self, $name ) = @_;
        $self->add_connect_hook("SET SCHEMA '$name'");
    },
    documentation =>
        'Name of postgresql schema where the publication record will be loaded, default is public, obviously ignored for other backend'
);

has 'plugin_namespace' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'Modware::Plugin::Import::Publication',
    documentation =>
        'Namespace of plugin module, default is Modware::Plugin::Import::Publication'
);

sub execute {
    my ($self) = @_;
    my $schema = $self->schema;
    my $logger = $self->output_logger;

    #load plugin
    $self->load_plugin(
        '+' . $self->plugin_namespace . '::' . $self->plugin );

    # do everything under a single transaction
    my $guard = $schema->txn_scope_guard;

    # creates/finds and caches all required cvterms
    $self->find_or_create_pub_type_cvterms;

    #$logger->debug("find/created all required pub_type cvterms");

    # map database column to bibtex fields
    my $pubmap = {
        title       => 'title',
        volume      => 'volume',
        series_name => 'journal',
        pyear       => 'year',
        pages       => 'pages',
    };

    # holds the pub data for each row of pub table
    my $pubhash;
    my $bib = BibTeX::Parser->new( IO::File->new( $self->input ) );
    while ( my $entry = $bib->next ) {
        if ( $entry->parse_ok ) {
            my $pubrow = $self->create_pub_record( $entry, $pubmap );
            $self->create_authors( $entry, $pubrow );
            $self->create_pub_properties( $entry, $pubrow );
        }
        else {
            $logger->warn( $entry->error );
        }
    }
    $guard->commit;
}

sub create_pub_record {
    my ( $self, $entry, $pubmap ) = @_;
    my $pubhash;
    $pubhash->{uniquename} = $self->parse_uniquename($entry);
    $pubhash->{pubplace}   = $self->parse_pub_source($entry);
    my $pub_type = $self->parse_pub_type($entry);
    $pubhash->{type_id} = $self->get_cvterm_row($pub_type)->cvterm_id;
    for my $column ( keys %$pubmap ) {
        $pubhash->{$column} = $entry->field( $pubmap->{$column} )
            if $entry->has( $pubmap->{$column} );
    }
    my $pubrow = $self->schema->resultset('Pub::Pub')->create($pubhash);
    return $pubrow;
}

sub create_pub_properties {
    my ( $self, $entry, $pubrow ) = @_;
    for my $prop (qw/doi status month issn abstract/) {
        if ( $entry->has($prop) ) {
            $self->schema->resultset('Pub::Pubprop')->create(
                {   pub_id  => $pubrow->pub_id,
                    type_id => $self->get_cvterm_row($prop)->cvterm_id,
                    value   => $entry->field($prop)
                }
            );
        }
    }
}

sub create_authors {
    my ( $self, $entry, $pubrow ) = @_;
    my $pub_id  = $pubrow->pub_id;
    my @authors = $entry->author;
    for my $i ( 0 .. $#authors ) {
        my $author_hash = {
            pub_id => $pub_id,
            rank   => $i + 1

        };
        if (my $first = $authors[$i]->first) {
            $first =~ s/{//;
            $first =~ s/}//;
            $author_hash->{givennames} = $first;
        }
        if (my $last = $authors[$i]->last) {
            $last =~ s/{//;
            $last =~ s/}//;
            $author_hash->{surname} = $last;
        }
        $self->schema->resultset('Pub::Pubauthor')->create($author_hash);
    }
}

sub find_or_create_pub_type_cvterms {
    my ($self) = @_;

    # first create the db entry
    $self->find_or_create_dbrow('pub_type');

    # now the cv namespace
    $self->find_or_create_cvrow('pub_type');

    # now create the cvterms
    for my $term (
        qw/unpublished journal_article status doi month issn abstract thesis/
        )
    {
        $self->find_or_create_cvterm_namespace( $term, 'pub_type',
            'pub_type' );
    }
}

sub ontology {
    return 'pub_type';
}

with 'Modware::Loader::Role::Ontology::WithHelper';
1;

__END__

=head1 NAME

Modware::Import::Command::bibtex2chado - Loads bibtex formatted file in chado database
