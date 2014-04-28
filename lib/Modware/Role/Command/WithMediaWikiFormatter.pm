
package Modware::Role::Command::WithMediaWikiFormatter;

use HTML::WikiConverter;
use Moose::Role;
use namespace::autoclean;
use XML::Twig;

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

    if ( $self->chado and $self->legacy_schema ) {
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
    }
    return $hash;
}

sub convert_to_mediawiki {

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
        if (    $ref->att('reference_no')
            and $self->has_pmid( $ref->att('reference_no') ) )
        {
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

    my $input = "<html><body>" . $self->trim($paragraph) . "</body></html>";
    my $wiki = $self->wiki_converter->html2wiki( html => $input );
    return $wiki;
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

=head1 DESCRIPTION

=cut
