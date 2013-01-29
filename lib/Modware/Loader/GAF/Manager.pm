
use strict;

package Modware::Loader::GAF::Manager;

use Moose;
use Moose::Util qw/ensure_all_roles/;
use MooseX::Attribute::Dependent;
use namespace::autoclean;
use Time::Piece;

has 'logger' => (
    is     => 'rw',
    isa    => 'Log::Log4perl::Logger',
    writer => 'set_logger'
);

has 'schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    writer  => 'set_schema',
    trigger => sub {
        my ( $self, $schema ) = @_;
        $self->_load_engine($schema);
    },
);

sub _load_engine {
    my ( $self, $schema ) = @_;
    $self->meta->make_mutable;
    $self->logger->debug('Setting up schema for Oracle');
    my $engine = 'Modware::Loader::Role::GAF::Chado::WithOracle';

    #if ( !check_install( module => $engine ) ) {
    #$engine = 'Modware::Loader::Role::Ontology::Chado::Generic';
    #}
    ensure_all_roles( $self, $engine );
    $self->meta->make_immutable;
}

has 'fcvtprop_rs' => (
    is      => 'ro',
    isa     => 'DBIx::Class::ResultSet',
    default => sub {
        my ($self) = @_;
        my $rs
            = $self->schema->resultset('Cv::Cvterm')
            ->search( { 'cv.name' => 'gene_ontology_association' },
            { join => 'cv', cache => 1, select => [qw/cvterm_id name/] } );
        return $rs;
    },
	lazy => 1
);

sub get_cvterm_for_feature_cvtermprop {
    my ( $self, $name ) = @_;
    $self->fcvtprop_rs->search( { name => $name } )->first->cvterm_id;
}

sub parse {

}

has 'feat_rs' => (
    is      => 'ro',
    isa     => 'DBIx::Class::ResultSet',
    default => sub {
        my ($self) = @_;
        return $self->schema->resultset('Sequence::Feature')->search(
            { 'type.name' => 'gene' },
            {   join   => [qw/dbxref type/],
                cache  => 1,
                select => [qw/dbxref.accession feature_id/]
            }
        );
    },
    lazy => 1
);

sub get_feature_id {
    my ( $self, $gene_id ) = @_;
    return $self->feat_rs->search( { 'dbxref.accession' => $gene_id } )
        ->first->feature_id;
}

has 'pub_rs' => (
    is      => 'ro',
    isa     => 'DBIx::Class::ResultSet',
    default => sub {
        my ($self) = @_;
        return $self->schema->resultset('Pub::Pub')
            ->search( {}, { cache => 1, select => 'pub_id' } );
    },
	lazy => 1
);

sub get_pub_id {
    my ( $self, $dbref ) = @_;
    $dbref =~ s/^[A-Z_]{4,7}://x;
    my $rs = $self->pub_rs->search( { uniquename => $dbref } );
    if ($rs) {
        return $rs->first_pub_id;
    }
}

sub prune {
    my ($self) = @_;
    $self->logger->warn('Pruning all annotations');
    $self->schema->storage->dbh_do(
        sub {
            my ( $storage, $dbh ) = @_;
            my $sth = $dbh->prepare(qq{DELETE FROM feature_cvterm});
            $sth->execute;
        }
    );
    $self->logger->info('Done pruning');
}

has '_ebi_goa_url' => (
    is  => 'ro',
    isa => 'Str',
    default =>
        'http://www.ebi.ac.uk/QuickGO/GAnnotation?format=gaf&db=dictyBase&limit=-1',
    lazy => 1
);

has '_ua' => (
    is      => 'ro',
    isa     => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
    lazy    => 1
);

sub query_ebi {
    my ($self) = @_;
    my $response = $self->_ua->get( $self->_ebi_goa_url );
    $response->is_success || die "NO GAF retrieved from EBI";
    my $t        = localtime;
    my $filename = 'dicty_' . $t->datetime . '.gaf';
    my $gaf_file = IO::File->new( $filename, 'w' );
    $gaf_file->write( $response->decoded_content );
    return $filename;
}

1;
