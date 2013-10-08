
package Modware::Export::Command::chado2genesummary;

use strict;
use feature 'say';

use HTML::WikiConverter;
use Moose;
use namespace::autoclean;
use XML::Twig;

extends qw/Modware::Export::Command/;
with 'Modware::Role::Command::WithLogger';

has 'legacy_dsn' => (
    is            => 'rw',
    isa           => 'Dsn',
    documentation => 'legacy database DSN',
    required      => 1
);

has 'legacy_user' => (
    is            => 'rw',
    isa           => 'Str',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'lu',
    documentation => 'legacy database user'
);

has 'legacy_password' => (
    is            => 'rw',
    isa           => 'Str',
    traits        => [qw/Getopt/],
    cmd_aliases   => [qw/lp lpass/],
    documentation => 'legacy database password'
);

has 'legacy_attribute' => (
    is            => 'rw',
    isa           => 'HashRef',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'lattr',
    documentation => 'Additional legacy database attribute',
    default       => sub {
        { 'LongReadLen' => 2**25, AutoCommit => 1 };
    }
);

has 'legacy_schema' => (
    is      => 'rw',
    isa     => 'Modware::Legacy::Schema',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    builder => '_build_legacy',
);

has wiki_converter => (
    is  => 'ro',
    isa => 'HTML::WikiConverter',
    default =>
        sub { return HTML::WikiConverter->new( dialect => 'MediaWiki' ) }
);

sub _build_legacy {
    my ($self) = @_;
    my $schema = Modware::Legacy::Schema->connect(
        $self->legacy_dsn,      $self->legacy_user,
        $self->legacy_password, $self->legacy_attribute
    );
    return $schema;
}

sub execute {
    my ($self) = @_;

    # my $feature_props = $self->chado->storage->dbh->selectall_arrayref(
    #     qq{
    # SELECT d.accession, fp.value
    # FROM featureprop fp
    # JOIN cvterm typ ON typ.cvterm_id = fp.type_id
    # JOIN feature f ON f.feature_id = fp.feature_id
    # JOIN dbxref d ON d.dbxref_id = f.dbxref_id
    # JOIN cvterm gene ON gene.cvterm_id = f.type_id
    # WHERE typ.name = 'paragraph_no'
    # AND gene.name = 'gene'
    # }
    # );

    my $tsv = Text::CSV->new( { sep_char => "\t" } );

    my $feature_para_rs
        = $self->chado->resultset('Sequence::Featureprop')->search(
        { 'type.name' => 'paragraph_no', 'type_2.name' => 'gene' },
        { join => [ 'type', { feature => [qw/type dbxref/] } ], }
        );

    while ( my $fp = $feature_para_rs->next ) {
        my $para_rs
            = $self->legacy_schema->resultset('Paragraph')
            ->find( { 'paragraph_no' => $fp->value },
            { select => [qw/me.written_by me.paragraph_text/] } );

        my $text = $self->extract_text( $para_rs->paragraph_text );
        my @array = ( $fp->feature->dbxref->accession, $para_rs->written_by,
            $text, "\n" );
        $tsv->print( $self->output_handler, \@array );
        say sprintf "%s\t%s\t%s\n", $fp->feature->dbxref->accession,
            $para_rs->written_by, $text;
    }
}

sub extract_text {
    my ( $self, $paragraph ) = @_;

    my $xml_parser = XML::Twig->new();
    my $xml        = $xml_parser->parse($paragraph);
    for my $gene ( $xml->descendants('locus') ) {
        my $ddbg_id      = $gene->att('gene_id');
        my $gene_symbol  = $gene->att('name');
        my $to_replace   = $gene->sprint();
        my $replace_with = "<a href=\"/gene/$ddbg_id\">$gene_symbol</a>";
        $paragraph =~ s/$to_replace/$replace_with/;
    }
    for my $go ( $xml->descendants('go') ) {
        my $go_id      = $go->att('id');
        my $go_term    = $go->att('term');
        my $to_replace = $go->sprint();
        my $replace_with
            = "<a href=\"/ontology/go/$go_id/annotation/page/1\">$go_term</a>";
        $paragraph =~ s/$to_replace/$replace_with/;
    }

    return $self->trim( $self->wiki_converter->html2wiki($paragraph) );
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/\n\r/ /g;
    $s =~ s/\t/ /g;
    $s =~ s/^\s+//g;
    $s =~ s/\s+$//g;
    return $s;
}

1;

__END__

=head1 NAME

Modware::Export::Command::chado2genesummary - Export gene summary for GFF3 sequence features

=head1 SYNOPSIS
=head1 DESCRIPTION
=head1 VERSION
=over
