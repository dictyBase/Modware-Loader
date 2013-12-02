
package generate_dicty_gpi;

use strict;
use feature 'say';
use Bio::Chado::Schema;
use IO::String;
use Modware::Legacy::Schema;
use Moose;
use namespace::autoclean;
use Text::CSV;
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
    documentation => 'dsn, user password for Oracle Chado schema'
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
        Modware::DataSource::Chado::BCS::Engine::Oracle->transform($schema);
        return $schema;
    }
);

has [qw/legacy_dsn legacy_user legacy_password/] => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'dsn, user, password for legacy Oracle schema'
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
    traits  => [qw/Hash/],
    traits  => [qw/NoGetopt/],
    handles => {
        get_gene_desc => 'get',
        has_gene_desc => 'defined'
    },
    lazy    => 1,
    builder => '_build_gene_desc'
);

sub _build_gene_desc {
    my ($self) = @_;

    my $rs = $self->_legacy_schema->resultset('LocusGp')
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
                = Time::Piece->strptime(
                    $row->locus_gene_product->date_created, "%d-%b-%y"
                )
            ];
        }
    }
    return { map { $_ => $_->[0] } keys %$gene_desc_cache };
}

has syns => (
    is      => 'rw',
    traits  => [qw/NoGetopt/],
    isa     => 'HashRef',
    traits  => [qw/Hash/],
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
    my $rs = $self->schema->resultset('Sequence::FeatureSynonym')->search({}, {prefetch => 'alternate_names'});
    while (my $row = $rs->next) {
        my $syns = [map {$_->name} $row->alternate_names];
        $synonym_cache->{$row->feature_id} = $syns if defined $syns;
     }
     return $synonym_cache;
}

has _taxon => (
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
        'http://dictybase.org/db/cgi-bin/dictyBase/download/download.pl?area=general&ID=DDB-GeneID-UniProt.txt',
    lazy => 1
);

has _uniprot_map => (
    is      => 'rw',
    traits  => [qw/NoGetopt/],
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    handles => {
        get_uniprot => 'get',
        has_uniprot => 'defined'
    },
    builder => '_build_uniprot_map'
);

sub _build_uniprot_map {
    my ($self) = @_;
    my $hash;
    my $ua       = LWP::UserAgent->new;
    my $response = $ua->get( $self->uniprot_map_file );
    if ( $response->is_success ) {
        my $content = $response->decoded_content;
        my $csv = Text::CSV->new( { binary => 1 } )
            or croak "Cannot use CSV: " . Text::CSV->error_diag();
        $csv->sep_char("\t");
        my $io = IO::String->new( $content, 'r' );
        while ( my $line = $io->getline() ) {
            if ( $csv->parse($line) ) {
                my @fields = $csv->fields();
                if ( !exists $hash->{ $fields[1] } ) {
                    $hash->{ $fields[1] } = [];
                }
                push $hash->{ $fields[1] }, 'UniProtKB:' . $fields[3]
                    if $fields[3];
            }
        }
        $io->close();
    }
    else {
        croak $response->status_line;
    }
    return $hash;
}

sub run {
    my ($self) = @_;

    my $out = IO::File->new( $self->output, 'w' );
    $out->print( $self->gpi_header . "\n" );

    my $feats = $self->_schema->storage->dbh->selectall_arrayref(
        qq{
		SELECT DISTINCT f.feature_id, d.accession, f.name, typ.name
		FROM feature f
		JOIN dbxref d ON d.dbxref_id = f.dbxref_id
		JOIN cvterm typ ON typ.cvterm_id = f.type_id
		JOIN organism o ON o.organism_id = f.organism_id
		WHERE typ.name = 'gene'
		AND o.common_name = 'dicty'
		}
    );

    for my $feat ( @{$feats} ) {

        my $gp = '';
        $gp = $self->get_gene_desc( $feat->[0] )
            if $self->has_gene_desc( $feat->[0] );

        my $syn  = '';
        my @syns = @{ $self->get_synonyms( $feat->[0] ) }
            if $self->has_synonyms( $feat->[0] );
        $syn = join( '|', @syns );

        my $db_xref  = '';
        my @uniprots = @{ $self->get_uniprot( $feat->[1] ) }
            if $self->has_uniprot( $feat->[1] );
        $db_xref = join( '|', @uniprots );

        my $parent_obj_id = '';
        my $gp_prop       = '';

        my $outstr = sprintf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",
            $feat->[1],
            $feat->[2], $gp,
            $syn, $feat->[3], $self->_taxon, $parent_obj_id, $db_xref,
            $gp_prop;
        $out->print($outstr);
    }
    $out->close();
    say "dicty GPI with "
        . scalar @{$feats}
        . " entries written to "
        . $self->output;
    return;
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
