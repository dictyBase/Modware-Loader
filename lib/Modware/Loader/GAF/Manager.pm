
use strict;

package Modware::Loader::GAF::Manager;

use Data::Dumper;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use namespace::autoclean;
use Time::Piece;

use Modware::Loader::GAF::Row;
with 'Modware::Loader::Role::GAF::Chado::WithOracle';
with 'Modware::Loader::Role::GAF::IdStash';

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
    my $engine = 'Modware::Loader::Role::GAF::Chado::WithOracle';
    ensure_all_roles( $self, $engine );
    $self->meta->make_immutable;
    $self->transform_schema($schema);
}

has 'fcvtprop_rs' => (
    is      => 'ro',
    isa     => 'DBIx::Class::ResultSet',
    default => sub {
        my ($self) = @_;
        return $self->schema->resultset('Cv::Cv')->search(
            { 'name' => 'gene_ontology_association' },
            { cache  => 1, select => 'cv_id' }
        );
    },
    lazy => 1
);

sub get_cvterm_for_feature_cvtermprop {
    my ( $self, $name ) = @_;
    return $self->fcvtprop_rs->first->cvterms->search( { 'name' => $name },
        { select => 'cvterm_id' } )->first->cvterm_id;
}

sub parse {
    my ( $self, $gaf_row ) = @_;
    chomp($gaf_row);
    return if $gaf_row =~ /^!/x;

    my @row_vals = split( "\t", $gaf_row );
    my $anno = Modware::Loader::GAF::Row->new;

    $anno->db( $row_vals[0] );
    $anno->gene_id( $row_vals[1] );
    $anno->gene_symbol( $row_vals[2] );
    $anno->qualifier( $row_vals[3] );
    $anno->go_id( $row_vals[4] );
    $anno->db_ref( $row_vals[5] );
    if ( $anno->db_ref =~ /\|/x ) {
        $anno = $self->handle_pubs($anno);
    }
    $anno->evidence_code( $row_vals[6] );
    $anno->with_from( $row_vals[7] );

    if ( $anno->with_from =~ /\|/x ) {
        $anno = $self->handle_dbxrefs($anno);
    }
    $anno->aspect( $row_vals[8] );
    $anno->taxon( $row_vals[12] );
    $anno->date( $row_vals[13] );
    $anno->assigned_by( $row_vals[14] );

    $anno->feature_id( $self->get_feature_id( $anno->gene_id ) );
    $anno->cvterm_id( $self->get_cvterm_id( $anno->go_id ) );
    $anno->pub_id( $self->find_pub_id( $anno->db_ref ) );
    $anno->cvterm_id_evidence_code(
        $self->find_cvterm_id_for_evidence_code( $anno->evidence_code ) );

    if ( $anno->is_valid() ) {
        return $anno;
    }
    else {
        return undef;
    }
}

sub handle_dbxrefs {
    my ( $self, $annotation ) = @_;
    my @dbxrefs = split( /\|/, $annotation->with_from );
    $annotation->with_from( $dbxrefs[0] );
    $self->find_or_create_dbxref_id( $dbxrefs[0] );
    for my $i ( 1 .. scalar(@dbxrefs) - 1 ) {
        my $dbxref_id = $self->find_or_create_dbxref_id( $dbxrefs[$i] );
        $annotation->set_additional_dbxref($dbxref_id);
    }
    return $annotation;
}

sub handle_pubs {
    my ( $self, $annotation ) = @_;
    my @pubs = split( /\|/, $annotation->db_ref );
    $annotation->db_ref( $pubs[0] );
    for my $i ( 1 .. scalar(@pubs) - 1 ) {
        my $pub_id = $self->find_pub_id( $pubs[$i] );
        next if !$pub_id;
        $annotation->set_additional_pub($pub_id);
    }
    return $annotation;
}

sub prune {
    my ($self) = @_;
    $self->logger->warn( 'Pruning '
            . $self->schema->resultset('Sequence::FeatureCvterm')
            ->search( {}, {} )->count
            . ' annotations' );
    $self->schema->storage->dbh_do(
        sub {
            my ( $storage, $dbh ) = @_;
            my $sth = $dbh->prepare(qq{DELETE FROM feature_cvterm});
            $sth->execute;
        }
    );
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
    my $filename = 'dicty_' . $t->mdy("") . '.gaf';
    my $gaf_file = IO::File->new( $filename, 'w' );
    $gaf_file->write( $response->decoded_content );
    return $filename;
}

1;
