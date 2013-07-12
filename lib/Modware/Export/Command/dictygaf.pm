
use strict;

package Modware::Export::Command::dictygaf;

use namespace::autoclean;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use Modware::Legacy::Schema;
extends qw/Modware::Export::GAF/;

with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Command::WithEmail';

has '+input'          => ( traits => [qw/NoGetopt/] );
has '+data_dir'       => ( traits => [qw/NoGetopt/] );
has '+output_handler' => ( traits => [qw/NoGetopt/] );

has '+source_url' => (
    default => 'www.dictybase.org',
    documentation =>
        'Canonical url for the source database,  default is www.dictybase.org'
);

has '+gafcv' => (
    default => 'gene_ontology_association',
    documentation =>
        'The cv namespace for storing gaf metadata such as source, with, qualifier and
        date column in chado database,  default is *gene_ontology_association*'
);

has '+date_term' => (
    default       => 'date',
    documentation => 'Cv term for storing date column,  default is *date*'
);

has '+with_term' => (
    default       => 'with',
    documentation => 'Cv term for storing with column,  default is *with*'
);

has '+source_term' => (
    default       => 'source',
    documentation => 'Cv term for storing source column,  default is *source*'
);

has '+qual_term' => (
    default => 'qualifier',
    documentation =>
        'Cv term for storing qualifier column,  default is *qualifier*'
);

has '+taxon_id' => (
    default       => 44689,
    documentation => 'The NCBI taxon id,  default is *44689*'
);

has '+source_database' => (
    default => 'dictyBase',
    documentation =>
        'The source database from which identifier is drawn,  represents column 1 of
        GAF2.0,  default is dictyBase'
);

has '+common_name' => ( default => 'dicty' );

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

has 'legacy' => (
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

sub get_description {
    my ( $self, $feat ) = @_;
    my $schema = $self->legacy;
    my $rs     = $schema->resultset('LocusGp')->search(
        { 'locus_no' => $feat->feature_id },
        { prefetch   => 'locus_gene_product' }
    );

    my $desc;
    my $date_created;
    while ( my $row = $rs->next ) {
        if ($date_created) {
            my $t
                = Time::Piece->strptime(
                $row->locus_gene_product->date_created, "%d-%b-%y" );
            if ( $date_created < $t ) {
                $desc         = $row->locus_gene_product->gene_product;
                $date_created = $t;
            }
        }
        else {
            $desc         = $row->locus_gene_product->gene_product;
            $date_created = Time::Piece->strptime(
                $row->locus_gene_product->date_created, "%d-%b-%y" );
        }

    }
    return $desc;
}

sub get_provenance {
    my ( $self, $row ) = @_;
    my $pub = $row->pub;
    if ( $pub->uniquename =~ /^PUB/ && $row->pub_id == 2 ) {
        return 'GO_REF:0000015';
    }
    elsif ( $pub->pubplace =~ /^PUBMED/ ) {
        return $self->pubmed_namespace . ':' . $pub->uniquename;
    }
    return $pub->pubplace . ':' . $pub->uniquename;
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

dictygaf - Dump GAF2.0 file for dictyBase from Chado database

=head1 SYNOPSIS

modware-export dictygaf -c <config.yaml>

=cut
