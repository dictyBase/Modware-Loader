package Modware::Export::Command::chadopub2bib;

use strict;
use Moose;
use namespace::autoclean;
use File::ShareDir qw/module_file/;
use XML::LibXML;
use XML::LibXSLT;
use LWP::UserAgent;
use Modware::Loader;
extends qw/Modware::Export::Chado/;

has '+organism' => ( traits        => [qw/NoGetopt/] );
has '+species'  => ( traits        => [qw/NoGetopt/] );
has '+genus'    => ( traits        => [qw/NoGetopt/] );
has '+input'    => ( traits        => [qw/NoGetopt/] );
has '+output'   => ( documentation => 'Name of the output bibtex file' );
has 'xslt'      => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        return module_file( "Modware::Loader", "pubmed2bibtex.xslt" );
    },
    documentation =>
        "Stylesheet file for xslt transformation, default is the one shipped with Loader"
);
has 'email' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => "Email to use for NCBI Eutils, mandatory"
);

sub execute {
    my ($self) = @_;
    my $xslt = XML::LibXSLT->new;
    my $style = XML::LibXML->load_xml( location => $self->xslt );
    my $parser = $xslt->parse_stylesheet($style);

    my $url
        = 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&tool=modware&email=dictybase@northwetern.edu&id=';
    my $agent = LWP::UserAgent->new();

    my $logger = $self->logger;
    my $schema = $self->schema;
    my $output = $self->output_handler;

    # Start with a paged resultset, 50 rows/page
    my $rs = $schema->resultset('Pub::Pub')
        ->search( { 'pubplace' => "PUBMED" }, { rows => 150, page => 1 } );
    my $pager = $rs->pager;
    for my $page ( $pager->first_page .. $pager->last_page ) {
        $logger->debug("fetching entries for page $page");
        my @pmids = map { $_->uniquename } $rs->page($page)->all;

        my $fetch_url = $url . join( ",", @pmids );
        my $resp = $agent->get($fetch_url);
        if ( $resp->is_error ) {
            my $msg = sprintf "Could not fetch because %s, error code:%d\n",
                $resp->message, $resp->code;
            $logger->logdie($msg);
        }

        my $pubxml = XML::LibXML->load_xml( string => $resp->content );
        my $results = $parser->transform($pubxml);
        $output->print( $parser->output_as_bytes($results) );
        $logger->debug("finished fetching for page $page");
        $logger->debug("going to wait....");
        sleep 55;
    }
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::chadopub2bib - Export pubmed literature from chado in bibtex format



