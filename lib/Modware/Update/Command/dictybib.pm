package Modware::Update::Command::dictybib;

use strict;

use Moose;
extends qw/Modware::Update::Command/;
use BibTeX::Parser;
use DateTime::Format::Strptime;

has '+input'  => ( documentation => 'Input bibtex file, default is STDIN' );
has '+output' => ( documentation => 'Output bibtex file, default is STDOUT' );
has 'datetime' => (
    is      => 'ro',
    isa     => 'DateTime::Format::Strptime',
    lazy    => 1,
    default => sub {
        return DateTime::Format::Strptime->new(
            pattern  => '%d-%b-%y',
            on_error => 'croak'
        );
    },
    traits => [qw/NoGetopt/]
);

sub execute {
    my ($self) = @_;
    my $schema = $self->schema;
    $self->setup_timestamp($schema);

    my $parser = BibTeX::Parser->new( $self->input_handler );
ENTRY:
    while ( my $entry = $parser->next ) {
        if ( $entry->parse_ok ) {
            next ENTRY if $entry->has('timestamp');

            my $row = $schema->resultset('Pub::Pub')
                ->find( { uniquename => $entry->cleaned_field('pmid') } );
            next ENTRY if !$row;

            if ( my $dt = $self->get_timestamp( $schema, $row ) ) {
                $self->bibtex( $entry, $dt );
            }
        }
        else {
            $self->logger->logdie( "Error parsing ", $entry->error );
        }
    }

}

sub setup_timestamp {
    my ( $self, $schema ) = @_;
    $schema->source('Pub::Pub')
        ->add_column( 'created_at' => { 'data_type' => 'date' } );
    $schema->class('Pub::Pub')
        ->register_column( 'created_at' => { 'data_type' => 'date' } );

}

sub get_timestamp {
    my ( $self, $schema, $row ) = @_;
    return $self->datetime->parse_datetime( $row->created_at );
}

sub bibtex {
    my ( $self, $entry, $dt ) = @_;
    my $output = $self->output_handler;
    $output->print( sprintf( "\@article{%s,\n", $entry->key ) );
    $output->print( $_, ' = {', $entry->field($_), '}', "\n" )
        for
        qw/journal title status nlmuniqueid pmid year/;
    for my $key (qw/volume pages doi month issn abstract/) {
        if ( $entry->has($key) ) {
            $output->print( $key, ' = {', $entry->field($key),
                '}', "\n" );

        }
    }
    $output->print( 'author = {', join( ' and ', $entry->author ),
        '}', "\n" );
    $output->print( 'timestamp = {', $dt->ymd('.'), '}', "\n" );
    $output->print( '}', "\n\n" );
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

Modware::Update::Command::dictybib - Update dicty bibtex file with timestamps


