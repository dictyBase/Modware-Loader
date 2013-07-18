package Modware::Export::Command::dictynonpub2bib;

use strict;
use Moose;
use namespace::autoclean;
extends qw/Modware::Export::Chado/;

has '+organism' => ( traits        => [qw/NoGetopt/] );
has '+species'  => ( traits        => [qw/NoGetopt/] );
has '+genus'    => ( traits        => [qw/NoGetopt/] );
has '+input'    => ( traits        => [qw/NoGetopt/] );
has '+output'   => ( documentation => 'Name of the output bibtex file' );

sub execute {
    my ($self) = @_;

    # Start with a list of non-pubmed sources
    my $schema = $self->schema;
    my $rs = $schema->resultset('Pub::Pub')->search(
        { 'pubplace' => { '!=', 'PUBMED' } },
        {   group_by => 'pubplace',
            select   => [ 'pubplace', { count => 'pub_id' } ]
        }
    );

    my $output = $self->output_handler;
    for my $source(map {$_->pubplace}$rs->all) {
        my $rs_source = $schema->resultset('Pub::Pub')->search({'pubplace' => $source});
        my $bib_id = lc $source;
        while (my $row = $rs_source->next) {
            $output->printf(sprintf("\@article{%s,\n",$bib_id.$row->uniquename));
            $output->print('journal = {{',$row->series_name,'}}', "\n") if $row->series_name;
            $output->print('volume = {',$row->volume,'}', "\n") if $row->volume;
            $output->print('year = {',$row->pyear,'}', "\n") if $row->pyear;
            $output->print('pages = {',$row->pages,'}', "\n") if $row->pages;
    }

}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::dictynonpub2bib - Export non-pubmed literature from dicty-chado in bibtex format



