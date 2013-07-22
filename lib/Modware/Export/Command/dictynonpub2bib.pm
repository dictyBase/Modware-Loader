package Modware::Export::Command::dictynonpub2bib;

use strict;
use Moose;
use namespace::autoclean;
use DateTime::Format::Strptime;
extends qw/Modware::Export::Chado/;

has '+organism' => ( traits        => [qw/NoGetopt/] );
has '+species'  => ( traits        => [qw/NoGetopt/] );
has '+genus'    => ( traits        => [qw/NoGetopt/] );
has '+input'    => ( traits        => [qw/NoGetopt/] );
has '+output'   => ( documentation => 'Name of the output bibtex file' );
has 'datetime'  => (
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
has 'timestamp' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 1,
    documentation => 'Export timestamp, default true'
);

sub execute {
    my ($self) = @_;

    # Start with a list of non-pubmed sources

    my $schema = $self->schema;

    if ( $self->timestamp ) {
        $schema->source('Pub::Pub')
            ->add_column( 'created_at' => { 'data_type' => 'date' } );
        $schema->class('Pub::Pub')
            ->register_column( 'created_at' => { 'data_type' => 'date' } );
    }

    my $rs = $schema->resultset('Pub::Pub')->search(
        { 'pubplace' => { '!=', 'PUBMED' } },
        {   group_by => 'pubplace',
            select   => [ 'pubplace', { count => 'pub_id' } ]
        }
    );

    for my $source ( map { $_->pubplace } $rs->all ) {
        my $rs_source = $schema->resultset('Pub::Pub')
            ->search( { 'pubplace' => $source } );
        my $bib_id = lc $source;
        while ( my $row = $rs_source->next ) {
            $self->bibtex( $row, $bib_id );
        }
        $self->logger->info("finished writing bibtex for source $source");
    }
}

sub bibtex {
    my ( $self, $row, $bib_id ) = @_;
    my $output = $self->output_handler;
    $output->print(
        sprintf( "\@article{%s,\n", $bib_id . $row->uniquename ) );
    $output->print( 'id = {', $row->uniquename, '}', "\n" );

    $output->print( 'journal = {{', $row->series_name, '}}', "\n" )
        if $row->series_name;
    $output->print( 'title = {{', $row->title, '}}', "\n" )
        if $row->title;

    $output->print( 'volume = {', $row->volume, '}', "\n" )
        if $row->volume;
    $output->print( 'year = {', $row->pyear, '}', "\n" )
        if $row->pyear;
    $output->print( 'pages = {', $row->pages, '}', "\n" )
        if $row->pages;

    my $prow = $row->search_related(
        'pubprops',
        { 'type.name' => 'abstract' },
        { join        => 'type', rows => 1 }
    )->single;
    $output->print( 'abstract = {', $prow->value, '}', "\n" )
        if $prow;

    my @author_list;
    for my $auth ( $row->pubauthors ) {
        my $auth_str;
        $auth_str .= $auth->surname if $auth->surname;
        $auth_str .= ', ' . $auth->givennames if $auth->givennames;
        push @author_list, $auth_str;
    }

    $output->print( 'author = {{', join( ' and ', @author_list ), '}}', "\n" )
        if @author_list;

    if ( $self->timestamp ) {
        my $dt = $self->datetime->parse_datetime( $row->created_at );
        $output->print( 'timestamp = {', $dt->ymd('.'), '}', "\n" );
    }
    $output->print( '}', "\n\n" );
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::dictynonpub2bib - Export non-pubmed literature from dicty-chado in bibtex format



