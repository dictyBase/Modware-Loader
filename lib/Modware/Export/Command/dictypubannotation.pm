package Modware::Export::Command::dictypubannotation;

use strict;
use Moose;
extends qw/Modware::Export::Chado/;

has '+input'    => ( traits => [qw/NoGetopt/] );
has '+organism' => ( traits => [qw/NoGetopt/] );
has '+species'  => ( traits => [qw/NoGetopt/] );
has '+genus'    => ( traits => [qw/NoGetopt/] );

sub execute {
    my ($self) = @_;
    my $schema = $self->schema;
    my $rs     = $schema->resultset('Pub::Pub')->search(
        {},
        {   join => 'feature_pubs'

        }
    );

    my $output = $self->output_handler;
    my $count  = 0;
    while ( my $row = $rs->next ) {
        my $anno;
        for my $fpub ( $row->feature_pubs ) {
            my $anno;
            for my $prop ( $fpub->feature_pubprops ) {
                push @$anno, $prop->type->name;
            }
            $output->print(
                sprintf( "%s\t%s\t%s\n",
                    $row->uniquename, $fpub->feature->dbxref->accession,
                    join( ':', @$anno ) )
            );
        }
        last if $count++ > 20;

    }
    $output->close;
}

__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Modware::Export::Command::dictypubannotation - Export literature annotations at dictybase
