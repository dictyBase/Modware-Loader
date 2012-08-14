package Modware::Load::Command::publink2dicty;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Email::Valid;
use File::Find::Rule;
use File::stat;
use Bio::Biblio::IO;
use Modware::DataSource::Chado;
use Modware::Publication::DictyBase;
use Try::Tiny;
use Carp;
use XML::LibXML;
extends qw/Modware::Load::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Command::WithEmail';

# Module implementation
#

has '+input' => (
    documentation =>
        'pubmedxml format file,  default is to pick up the latest from data dir,  file name that matches pubmed_links_[datestring].xml',
    default => sub {
        my $self = shift;
        my @files = map { $_->[1] }
            sort { $b->[0] <=> $a->[0] }
            map { [ stat($_)->mtime, $_ ] }
            File::Find::Rule->file->name(qr/^pubmed\_links\_\d+\.xml$/)
            ->in( $self->data_dir );
        croak "no input file found\n" if !@files;
        $files[0];
    },
    lazy => 1
);

has 'xpath_query' => (
    is   => 'rw',
    isa  => 'XML::LibXML::XPathExpression',
    lazy => 1,
    documentation =>
        'A XML::LibXML::XPathExpression object representing a query to find
         the full text links in a pubmed xml file. Default expression is
         <eLinkResult/LinkSet/IdUrlList/IdUrlSet[Id and ObjUrl/Url]',
    default => sub {
        return XML::LibXML::XPathExpression->new(
            'eLinkResult/LinkSet/IdUrlList/IdUrlSet[Id and ObjUrl/Url]');
    }
);

sub execute {
    my $self = shift;
    my $log  = $self->dual_logger;
    $self->subject('Pubmed link loader robot');

    Modware::DataSource::Chado->connect(
        dsn      => $self->dsn,
        user     => $self->user,
        password => $self->password,
        attr     => $self->attribute
    );

    $log->debug("going to parse file ",  $self->input);

    my $xml = XML::LibXML->new->parse_file( $self->input );
    if ( !$xml->exists( $self->xpath_query ) ) {
        $log->warn( 'No full text links found in ', $self->input, 'file' );
        return;
    }

    my $updated = 0;
    my $error   = 0;

    for my $node ( $xml->findnodes( $self->xpath_query ) ) {
        my $pubmed_id = $node->findvalue('Id');
        my $url       = $node->findvalue('ObjUrl/Url');

        if ( my $dicty_pub
            = Modware::Publication::DictyBase->find_by_pubmed_id($pubmed_id) )
        {
            $dicty_pub->full_text_url($url);
            try {
                $dicty_pub->update;
                $log->info("updated full text url for pubmed_id: $pubmed_id");
                $updated++;
            }
            catch {
                $log->error(
                    "Error in updating full text url with pubmed id: $pubmed_id"
                );
                $log->error($_);
                $error++;
            };
        }
        else {
            $log->warn("Cannot find publication with pubmed id: $pubmed_id");
        }
    }
    $log->info("Updated: $updated\tError: $error");
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Load pubmed full text url in dicty chado database

