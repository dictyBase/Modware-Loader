package Modware::Update::Command::pubindicty;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::DB::EUtilities;
use Modware::DataSource::Chado;
use Modware::Publication::DictyBase;
use Try::Tiny;
use Carp;
use XML::LibXML;
extends qw/Modware::Update::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Command::WithEmail';

# Module implementation
#

has '+input'    => ( traits => [qw/NoGetopt/] );
has '+data_dir' => ( traits => [qw/NoGetopt/] );

has 'threshold' => (
    is      => 'ro',
    isa     => 'Int',
    default => 20,
    traits  => [qw/NoGetopt/]
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

has 'status' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'aheadofprint',
    documentation =>
        'Status of published article that will be searched for update,  default is *aheadofprint*'
);

has 'update_flag' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    traits  => [qw/Bool NoGetopt/],
    handles => {
        'set_update_flag'   => 'set',
        'unset_update_flag' => 'unset',
        'needs_no_update'   => 'not'
    }
);

sub execute {
    my $self = shift;
    my $log  = $self->dual_logger;
    $self->subject('Pubmed update robot');

    Modware::DataSource::Chado->connect(
        dsn      => $self->dsn,
        user     => $self->user,
        password => $self->password,
        attr     => $self->attribute
    );

    my $ids;
    my $itr
        = Modware::Publication::DictyBase->search( status => $self->status );
    $self->set_total_count( $itr->count );
    $log->info( "Going to process ",
        $self->total_count, " ", $self->status, " pubmed records" );

PUB:
    while ( my $pub = $itr->next ) {
        push @$ids, $pub->pubmed_id;
        if ( @$ids >= $self->threshold ) {
            $log->info( "processing ids\n", join( "\n", @$ids ) );
            $self->process_id($ids);
            undef $ids;
        }
    }

    if (@$ids) {    ## -- leftover
        $log->info( "processing ids\n", join( "\n", @$ids ) );
        $self->process_id($ids);
    }

    $log->info( 'updated:', $self->update_count, ' error:',
        $self->error_count );

}

sub process_id {
    my ( $self, $ids ) = @_;
    my $log = $self->current_logger;

    my $eutils = Bio::DB::EUtilities->new(
        -eutil  => 'elink',
        -dbfrom => 'pubmed',
        -cmd    => 'prlinks',
        -id     => [$ids],
        -email  => $self->from
    );

    my $res = $eutils->get_Response;
    if ( $res->is_error ) {
        $log->error( $res->code, "\t", $res->message );
        return;
    }

    my $xml = XML::LibXML->load_xml( string => $res->content );
    if ( !$xml->exists( $self->xpath_query ) ) {
        $log->warn('No full text links found');
        return;
    }

NODE:
    for my $node ( $xml->findnodes( $self->xpath_query ) ) {
        my $pubmed_id = $node->findvalue('Id');
        my $url       = $node->findvalue('ObjUrl/Url');

        my $dicty_pub
            = Modware::Publication::DictyBase->find_by_pubmed_id($pubmed_id);

        if ($dicty_pub) {
            if ( $dicty_pub->has_full_text_url ) {
                if ( $dicty_pub->full_text_url ne $url ) {
                    $dicty_pub->full_text_url($url);
                    $log->info( "updated full text url to $url" );
                    $self->set_update_flag;
                }
            }
            else {
                $log->info(
                    "$pubmed_id has no full text url: going for update to $url"
                );
                $dicty_pub->full_text_url($url);
                $self->set_update_flag;
            }

  # -- status is always present for existing pubmed record so no need to check
  # for its absence
            if ( my $status = $self->fetch_pubmed_status($pubmed_id) ) {
                if ( $status ne $dicty_pub->status ) {
                    $dicty_pub->status($status);
                    $log->info("updated status to $status");
                    $self->set_update_flag;
                }
            }

            if ( $self->needs_no_update ) {
                $log->info("record $pubmed_id do not need update");
                next NODE;
            }

            try {
                $dicty_pub->update;
                $log->info("updated record with pubmed id: $pubmed_id");
                $self->inc_update;
                $self->unset_update_flag;
            }
            catch {
                $log->error(
                    "Error in updating full text url with pubmed id: $pubmed_id"
                );
                $log->error($_);
                $self->inc_error;
            };
        }
        else {
            $log->warn("Cannot find publication with pubmed id: $pubmed_id");
        }
    }
    return 1;
}

sub fetch_pubmed_status {
    my ( $self, $id ) = @_;
    my $eutil = Bio::DB::EUtilities->new(
        -eutil => 'esummary',
        -db    => 'pubmed',
        -id    => $id,
        -email => $self->from
    );

    my $res = $eutil->get_Response;
    if ( $res->is_error ) {
        $self->current_logger->error( $res->code, "\t", $res->message );
        return;
    }

    my $dom = XML::LibXML->load_xml( string => $res->content );
    if ( $dom->exists('//Item[@Name="PubStatus"]') ) {
        my $status = $dom->findvalue('//Item[@Name="PubStatus"]');
        return $status;
    }

}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Update full text url of pubmed records in dicty chado database

