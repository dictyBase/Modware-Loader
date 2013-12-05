
package generate_dicty_gpi;

use strict;
use feature 'say';
use Bio::Chado::Schema;
use IO::String;
use IO::Uncompress::Gunzip qw/gunzip $GunzipError/;
use Modware::Legacy::Schema;
use Moose;
use namespace::autoclean;
use Time::Piece;
use autodie qw/open close/;
use Modware::DataSource::Chado::BCS::Engine::Oracle;
with 'MooseX::Getopt';

has output => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    default       => 'dicty_gpi.tsv',
    documentation => 'Outfile file to write dictyBase GPI'
);

has gpi_header => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    default => sub {
        return sprintf "%s\n%s", '!gpi-version: 1.1', '!namespace: dictyBase';
    }
);

has [qw/dsn user password/] => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'credentials for Oracle Chado schema'
);

has schema => (
    is      => 'rw',
    traits  => [qw/NoGetopt/],
    isa     => 'Bio::Chado::Schema',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $schema = Bio::Chado::Schema->connect( $self->dsn, $self->user,
            $self->password, { LongReadLen => 2**25 } );
        Modware::DataSource::Chado::BCS::Engine::Oracle->new->transform(
            $schema);
        return $schema;
    }
);

has [qw/legacy_dsn legacy_user legacy_password/] => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'credentials for legacy Oracle schema'
);

has legacy_schema => (
    is      => 'rw',
    isa     => 'Modware::Legacy::Schema',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return Modware::Legacy::Schema->connect(
            $self->legacy_dsn, $self->legacy_user,
            $self->legacy_password, { LongReadLen => 2**25 }
        );
    }
);

has gene_desc => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/NoGetopt Hash/],
    handles => {
        get_gene_desc => 'get',
        has_gene_desc => 'defined'
    },
    lazy    => 1,
    builder => '_build_gene_desc'
);

sub _build_gene_desc {
    my ($self) = @_;

    my $rs = $self->legacy_schema->resultset('LocusGp')
        ->search( {}, { prefetch => 'locus_gene_product' } );

    my $gene_desc_cache;
    while ( my $row = $rs->next ) {
        if ( exists $gene_desc_cache->{ $row->locus_no } ) {
            my $date_created = Time::Piece->strptime(
                $row->locus_gene_product->date_created, "%d-%b-%y" );
            if ( $date_created > $gene_desc_cache->{ $row->locus_no }->[1] ) {
                $gene_desc_cache->{ $row->locus_no }
                    = [ $row->locus_gene_product->gene_product,
                    $date_created ];
            }
        }
        else {
            $gene_desc_cache->{ $row->locus_no } = [
                $row->locus_gene_product->gene_product,
                Time::Piece->strptime(
                    $row->locus_gene_product->date_created, "%d-%b-%y"
                )
            ];
        }
    }
    return {
        map { $_ => $gene_desc_cache->{$_}->[0] }
            keys %$gene_desc_cache
    };
}

has syns => (
    is      => 'rw',
    traits  => [qw/NoGetopt Hash/],
    isa     => 'HashRef',
    handles => {
        get_synonyms => 'get',
        has_synonyms => 'defined'
    },
    lazy    => 1,
    builder => '_build_synonyms'
);

sub _build_synonyms {
    my ($self) = @_;
    my $synonym_cache;
    my $rs = $self->schema->resultset('Sequence::FeatureSynonym')
        ->search( {}, { prefetch => 'alternate_name' } );
    while ( my $row = $rs->next ) {
        push @{ $synonym_cache->{ $row->feature_id } },
            $row->alternate_name->name;
    }
    return $synonym_cache;
}

has taxon => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => 'taxon:44689'
);

has uniprot_map_file => (
    is     => 'rw',
    traits => [qw/NoGetopt/],
    isa    => 'Str',
    default =>
        'http://www.geneontology.org/gp2protein/gp2protein.dictyBase.gz',
    lazy => 1
);

has uniprot_map => (
    is      => 'rw',
    traits  => [qw/NoGetopt Hash/],
    isa     => 'HashRef',
    lazy    => 1,
    handles => {
        get_uniprot => 'get',
        has_uniprot => 'defined'
    },
    builder => '_build_uniprot_map'
);

sub _build_uniprot_map {
    my ($self)   = @_;
    my $ua       = LWP::UserAgent->new;
    my $response = $ua->get( $self->uniprot_map_file );
    my $id_cache;
    if ( $response->is_success ) {
        my $content = $response->decoded_content;
        my $output;
        gunzip \$content => \$output or die "gunzip failed: $GunzipError\n";
        my $io = IO::String->new( $output, 'r' );
        LINE:
        while ( my $line = $io->getline() ) {
            next LINE if $line =~ /^!/;
            chomp $line;
            my ( $mod, $map ) = split /\t/, $line;
            my ($mod_id) = ( ( split /:/, $mod ) )[1];
            if ( $map =~ /\;/ ) {
                for my $other ( split /\;/, $map ) {
                    push @{ $id_cache->{$mod_id} }, $other if $other =~ /UniProt/;
                }
            }
            else {
                push @{ $id_cache->{$mod_id} }, $map;
            }

        }
        $io->close();
    }
    else {
        die $response->status_line;
    }
    return $id_cache;
}

sub run {
    my ($self) = @_;

    my $out = IO::File->new( $self->output, 'w' );
    $out->print( $self->gpi_header . "\n" );

    my $rs = $self->schema->resultset('Sequence::Feature')->search(
        {   'organism.common_name' => 'dicty',
            'type.name'            => 'gene',
            'is_deleted'           => 0
        },
        { join => [qw/type organism/], prefetch => 'dbxref' }
    );

    my $empty_column = '';
    GENE:
    while ( my $row = $rs->next ) {
        next GENE if $row->name =~ /_ps\d{0,1}$/;
        my $feature_id = $row->feature_id;
        my $gene_id = $row->dbxref->accession;
        my $gp
            = $self->has_gene_desc($feature_id)
            ? $self->get_gene_desc($feature_id)
            : '';
        my $syn
            = $self->has_synonyms($feature_id)
            ? join( '|', @{ $self->get_synonyms($feature_id) } )
            : '';
        my $dbxref
            = $self->has_uniprot($gene_id)
            ? join( '|', @{ $self->get_uniprot($gene_id) } )
            : '';

        my $outstr = sprintf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
            $row->dbxref->accession,
            $row->name, $gp,
            $syn, 'gene', $self->taxon, $empty_column, $dbxref,
            $empty_column;
        $out->print($outstr);
    }
    $out->close();
}

1;

package main;
generate_dicty_gpi->new_with_options->run();

1;

__END__

=head1 NAME

generate_dicty_gpi - Script to generate a dictyBase GPI file

=head1 DESCRIPTION

GPI is a gene product information file. dictyBase uses it to enhance the literature curation pipeline.

=head1 SYNOPSIS

perl -Ilib maint/generate_dicty_gpi.pl --dsn '' --user '' --password '' --legacy_dsn '' --legacy_user '' --legacy_password ''

=cut
