
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

sub _build_legacy {
    my ($self) = @_;
    my $schema = Modware::Legacy::Schema->connect(
        $self->legacy_dsn,      $self->legacy_user,
        $self->legacy_password, $self->legacy_attribute
    );
    return $schema;
}

has wiki_converter => (
    is  => 'ro',
    isa => 'HTML::WikiConverter',
    default =>
        sub { return HTML::WikiConverter->new( dialect => 'MediaWiki' ) },
    required => 1
);

has _pmids => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => {
        get_pmid => 'get',
        has_pmid => 'defined'
    },
    lazy    => 1,
    builder => '_build_pub_id_pmid'
);

sub _build_pub_id_pmid {
    my ($self) = @_;
    my $hash;

    my $pub_rs = $self->chado->resultset('Pub::Pub')->search(
        {},
        {   select       => [qw/me.uniquename me.pub_id/],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator'
        }
    );
    while ( my $pubref = $pub_rs->next ) {
        $hash->{ $pubref->{pub_id} } = $pubref->{uniquename};
    }

    # Few reference_no are used from legacy Reference table
    my $ref_rs = $self->legacy_schema->resultset('Reference')->search(
        { 'me.ref_source' => 'PUBMED' },
        {   select       => [qw/me.reference_no me.pubmed/],
            result_class => 'DBIx::Class::ResultClass::HashRefInflator'
        }
    );
    while ( my $refref = $ref_rs->next ) {
        $hash->{ $refref->{reference_no} } = $refref->{pubmed}
            if !exists $hash->{ $refref->{reference_no} };
    }

    return $hash;
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

    # my $feature_para_rs
    #     = $self->chado->resultset('Sequence::Featureprop')->search(
    #     { 'type.name' => 'paragraph_no', 'type_2.name' => 'gene' },
    #     {   join => [ 'type', { feature => [qw/type dbxref/] } ],
    #         result_class => 'DBIx::Class::ResultClass::HashRefInflator'
    #     }
    #     );

    # while ( my $fp = @{$feature_props} ) {
    for my $fp ( @{$feature_props} ) {
        my $para_rs
            = $self->legacy_schema->resultset('Paragraph')
            ->find( { 'paragraph_no' => $fp->[1] },
            { select => [qw/me.written_by me.paragraph_text/] } );

        my $wiki
            = $self->convert_xml_to_mediawiki( $para_rs->paragraph_text );
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

sub convert_xml_to_mediawiki {
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
    for my $ref ( $xml->descendants('reference') ) {
        my $pmid;
        if ( $ref->att('reference_no') ) {
            $pmid = $self->get_pmid( $ref->att('reference_no') );
        }
        elsif ( $ref->att('pmid') ) {
            $pmid = $ref->att('pmid');
        }
        if ($pmid) {
            my $to_replace = $ref->sprint();
            my $ref_text   = $ref->text;
            my $replace_with
                = "<a href=\"http://www.ncbi.nlm.nih.gov/pubmed/$pmid\">$ref_text</a>";

            # Regex metacharacters can exist in reference tags, thus \Q...\E
            $paragraph =~ s/\Q$to_replace\E/$replace_with/;
        }
        else {
            $self->logger->warn( "PMID does not exist for reference_no:"
                    . $ref->att('reference_no') );
        }
    }
    my $html = $self->trim($paragraph);
    return $self->wiki_converter->html2wiki($html);
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/[\n\r]//g;
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

Command to export gene summaries & curation status notes to MediaWiki format. 
Currently, it is in XML with custom implicit tags which are rendered as link on the front-end. 
This command replaces such tags/links with proper 'href' for efficient conversion to MediaWiki.

=cut
