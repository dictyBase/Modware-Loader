
package Modware::Export::Command::chado2genesummary;

use strict;
use feature 'say';

use Moose;
use namespace::autoclean;

extends qw/Modware::Export::Command/;
with 'Modware::Role::Command::WithLogger';

has 'legacy_schema' => (
    is      => 'rw',
    isa     => 'Modware::Legacy::Schema',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    builder => '_build_legacy',
);

with 'Modware::Role::Command::WithMediaWikiFormatter';

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

sub _build_legacy {
    my ($self) = @_;
    my $schema = Modware::Legacy::Schema->connect(
        $self->legacy_dsn,      $self->legacy_user,
        $self->legacy_password, $self->legacy_attribute
    );
    return $schema;
}

has _proper_names => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub {
        {   PF           => 'Petra Fey',
            CGM_DDB_PFEY => 'Petra Fey',
            RD           => 'Robert Dodson',
            CGM_DDB_BOBD => 'Robert Dodson',
            PG           => 'Pascale Gaudet',
            CGM_DDB_PASC => 'Pascale Gaudet',
            CGM_DDB_KPIL => 'Karen Kestin'
        };
    },
    handles => {
        get_author_name => 'get',
        has_author_name => 'defined'
    },
    lazy => 1,
);

sub execute {
    my ($self) = @_;

    $self->logger->info("Exporting gene summaries");

    my $feature_props = $self->chado->storage->dbh->selectall_arrayref(
        qq{
    SELECT d.accession, fp.value
    FROM featureprop fp
    JOIN cvterm typ ON typ.cvterm_id = fp.type_id
    JOIN feature f ON f.feature_id = fp.feature_id
    JOIN dbxref d ON d.dbxref_id = f.dbxref_id
    JOIN cvterm gene ON gene.cvterm_id = f.type_id
    WHERE typ.name = 'paragraph_no'
    AND gene.name = 'gene'
    }
    );
    $self->logger->debug(
        scalar @{$feature_props}
            . " gene summaries to export, as per Sequence::Featureprops" );

    for my $fp ( @{$feature_props} ) {
        my $para_rs
            = $self->legacy_schema->resultset('Paragraph')
            ->find( { 'paragraph_no' => $fp->[1] },
            { select => [qw/me.written_by me.paragraph_text/] } );

        my $wiki    = $self->convert_to_mediawiki( $para_rs->paragraph_text );
        my $ddbg_id = $fp->[0];
        my $author
            = ( $self->has_author_name( $para_rs->written_by ) )
            ? $self->get_author_name( $para_rs->written_by )
            : $para_rs->written_by;

        my $outstr = sprintf "%s\t%s\t%s\n", $ddbg_id, $author, $wiki;
        $self->output_handler->print($outstr);
    }
    $self->output_handler->close();
    $self->logger->info(
        "Export completed. Output written to " . $self->output );
}

1;

__END__

=head1 NAME

Modware::Export::Command::chado2genesummary - Export gene summary for GFF3 sequence features

=head1 SYNOPSIS

=head1 DESCRIPTION

Command to export gene summaries & curation status notes to MediaWiki format. 
Currently, it is in XML with custom implicit tags which are rendered as link on the front-end. 
This command replaces such tags/links with proper 'href' for efficient conversion to MediaWiki.

=cut
