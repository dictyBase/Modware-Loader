package Modware::Transform::Command::pub2bib;
use strict;
use Moose;
use XML::LibXML;
use XML::LibXSLT;
use LWP::UserAgent;
use Cwd;
use Path::Class::File;
use Modware::Loader;
use File::ShareDir qw/module_file/;

extends qw/Modware::Transform::Command/;
has 'xslt' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        return module_file( "Modware::Loader", "pubmed2bibtex.xslt" );
    },
    documentation =>
        "Stylesheet file for xslt transformation, default is the one shipped with Loader"
);
has 'xml_output' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'Name of the xml output file, required'
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
        = 'http://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi?db=pubmed&retmode=xml&tool=modware&email=';
    $url .= $self->email . '&id=';
    my @entries = $self->input_handler->getlines();
    $url .= join( ",", @entries );

    my $logger      = $self->logger;
    my $xml_handler = Path::Class::File->new( $self->xml_output )->openw;

    $logger->debug( "going to fetch ", scalar @entries, " entries" );
    my $agent = LWP::UserAgent->new();
    my $resp  = $agent->get($url);
    if ( $resp->is_error ) {
        my $msg = sprintf "Could not fetch because %s, error code:%d\n",
            $resp->message, $resp->code;
        $logger->logdie($msg);
    }

    #output
    $xml_handler->print( $resp->content );
    $xml_handler->close;
    $logger->debug("written xml output");

    my $pubxml = XML::LibXML->load_xml( string => $resp->content );
    my $results = $parser->transform($pubxml);
    $self->output_handler->print( $parser->output_as_bytes($results) );
    $logger->debug("written bibtex output");

}

__PACKAGE__->meta->make_immutable;
1;
__END__

=head1 NAME

Modware::Transform::Command::pub2bib - Export pubmed literature in bibtex format

