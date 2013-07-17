package Modware::Export::Command::chadopub2bib;

use strict;
use Moose;
use namespace::autoclean;
use File::ShareDir qw/module_file/;
use XML::LibXML;
use XML::LibXSLT;
use LWP::UserAgent;
use Modware::Loader;
use Time::Piece;
use Cwd;
use Path::Class::Dir;
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
has 'entries' => (
    is      => 'rw',
    isa     => 'Int',
    lazy    => 1,
    default => sub {
        return 200;
    },
    documentation =>
        'No of pubmed entries retrieved per request, default is 200'
);
has 'wait' => (
    is   => 'rw',
    isa  => 'Int',
    lazy => 1,
    documentation =>
        'No of secs to wait between every request, default is 60 secs/1 min',
    default => sub { return 60 }
);

has 'xmldump' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub { getcwd() },
    documentation =>
        'Name of the folder where the pubmed xml content will be dumped, default is current folder'
);

sub execute {
    my ($self) = @_;
    my $xslt = XML::LibXSLT->new;
    my $style = XML::LibXML->load_xml( location => $self->xslt );
    my $parser = $xslt->parse_stylesheet($style);

    my $url
        = 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&tool=modware&email=';
    $url .= $self->email . '&id=';
    my $agent = LWP::UserAgent->new();

    my $logger = $self->logger;
    my $schema = $self->schema;
    my $output = $self->output_handler;
    my $count  = 0;
    my $xml_dir = Path::Class::Dir->new($self->xmldump);

    # Start with a paged resultset, 50 rows/page
    my $rs
        = $schema->resultset('Pub::Pub')->search( { 'pubplace' => "PUBMED" },
        { rows => $self->entries, page => 1 } );
    my $pager = $rs->pager;
    for my $page ( $pager->first_page .. $pager->last_page ) {
        my $paged_rs = $rs->page($page);
        $count += $paged_rs->count;
        $logger->debug(
            "fetching entries ",
            $paged_rs->count,
            " for page $page"
        );
        my @pmids = map { $_->uniquename } $paged_rs->all;

        my $fetch_url = $url . join( ",", @pmids );
        my $resp = $agent->get($fetch_url);
        if ( $resp->is_error ) {
            my $msg = sprintf "Could not fetch because %s, error code:%d\n",
                $resp->message, $resp->code;
            $logger->logdie($msg);
        }

        my $content = $resp->content;
        $logger->debug("finished fetching for page $page");

        my $t = Time::Piece->new;
        my $xml_file = $t->ymd('-').'-'.$t->hms('-').'-dictypub.xml';
        my $xml_handler = $xml_dir->file($xml_file)->openw;
        $xml_handler->print($content);
        $xml_handler->close;
        $logger->debug("dumped xml content in $xml_file");



        my $pubxml = XML::LibXML->load_xml( string => $content );
        my $results = $parser->transform($pubxml);
        $output->print( $parser->output_as_bytes($results) );
        $logger->debug("converted bibtex for page $page");

        $logger->debug( "now going to wait for ", $self->wait, " secs for the next retreival ...." );
        sleep $self->wait;
    }
    $logger->info("fetched total of $count entries from database");
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::chadopub2bib - Export pubmed literature from chado in bibtex format



