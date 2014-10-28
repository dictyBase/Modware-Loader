package Modware::Export::Command::curatornotes;

use strict;
use Moose;
use namespace::autoclean;
use Text::CSV;
use Moose::Util::TypeConstraints;
extends qw/Modware::Export::CommandPlus/;
with 'Modware::Role::Command::WithDBI';
with 'Modware::Role::Command::WithIO';

has '+input' => ( traits => [qw/NoGetopt/] );

has 'statement' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => q{
        SELECT featureprop.value note, dbxref.accession
            FROM featureprop 
            JOIN feature ON
                featureprop.feature_id = feature.feature_id
            JOIN cvterm ON
                cvterm.cvterm_id = featureprop.type_id
            JOIN cvterm ftype ON
               feature.type_id = ftype.cvterm_id
            JOIN dbxref ON
                dbxref.dbxref_id = feature.dbxref_id
            WHERE
                ftype.name = 'gene'
                AND
                feature.is_deleted = 0
                AND
                cvterm.name = ?
            ORDER BY dbxref.accession
    }
);

has '_gene_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        add_gene            => 'set',
        has_gene            => 'exists',
        get_gene            => 'get',
        get_genes_and_notes => 'kv',
        prune_genes         => 'clear'
    }
);

has 'note' => (
    is => 'rw',
    isa => enum(['public', 'private']),
    required => 1,
    documentation => 'Type of curator notes, could be either of public or private'
);

sub execute {
    my ($self) = @_;
    my $dbh    = $self->dbh;
    my $sth    = $dbh->prepare( $self->statement );
    my $note = $self->note eq 'public' ? 'public note': 'private note';
    $sth->execute($note);
    my $output = $self->output_handler;
    my $csv = Text::CSV->new( { auto_diag => 1, binary => 1 } );
    $csv->print( $output, [ "Gene ID", "Notes" ] );
    $output->print("\n");
    while ( my $hashref = $sth->fetchrow_hashref('NAME_lc') ) {
        if ( $self->has_gene( $hashref->{accession} ) ) {
            my $note_value = $self->get_gene( $hashref->{accession} );
            push @$note_value, $hashref->{note};
        }
        else {
            for my $pair ( $self->get_genes_and_notes ) {
                $csv->print($output, [$pair->[0], @{$pair->[1]}]);
                $output->print("\n");
            }
            $self->prune_genes;
            $self->add_gene( $hashref->{accession},
                [ $hashref->{note} ] );
        }
    }
}

1;

__END__

=head1 NAME

Modware::Export::Command::curatornotes - Export a csv format of genes and its associated curator notes
