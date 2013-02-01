
use autodie;
use strict;
use warnings;

package Modware::Load::Command::ebigaf2chado;

use Bio::Chado::Schema;
use IO::String;
use Moose;
use namespace::autoclean;
use Time::Piece;

extends qw/Modware::Load::Chado/;

has '+input'         => ( documentation => 'Name of the GAF file' );
has '+input_handler' => ( traits        => [qw/NoGetopt/] );

has 'prune' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 1,
    lazy          => 1,
    documentation => 'Delete all annotations before loading, default is ON'
);

has 'print_gaf' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    lazy          => 1,
    documentation => 'Print GAF'
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;
    $logger->info( "Loading config from " . $self->configfile );
    my $schema = $self->transform( $self->schema );

    my $gaf_manager = GAFManager->new;
    $gaf_manager->schema($schema);
    $gaf_manager->logger($logger);
    $gaf_manager->init();

    my $guard = $self->schema->storage->txn_scope_guard;

    if ( $self->prune ) {
        $logger->warn('Pruning all annotations.');

#my $prune_count = $schema->resultset('Sequence::FeatureCvterm')->search()->count;

        $schema->storage->dbh_do(
            sub {
                my ( $storage, $dbh ) = @_;
                my $sth = $dbh->prepare(qq{DELETE FROM feature_cvterm});
                $sth->execute;
            }
        );
        $logger->info("Done! with pruning. ")
            ;    # . $prune_count . " records deleted." );
    }

    my $io;
    if ( $self->input ) {
        $io = IO::File->new( $self->input, 'r' );
        $logger->info( "Reading from " . $self->input );
    }
    else {
        my $ebi_query = EBIQuery->new;
        my $response  = $ebi_query->query_ebi();
        $io = IO::String->new;
        $io->open($response);
        $logger->info("No file provided. Querying EBI.");
        my $t = localtime;
        my $bak_file = IO::File->new( 'dicty_' . $t->datetime . '.gaf', 'w' );
        $bak_file->write($response);
        $bak_file->close;
    }
    while ( my $gaf = $io->getline ) {
        my @annotations = $gaf_manager->parse($gaf);
        if ( !@annotations ) {
            next;
        }
        foreach my $anno (@annotations) {
            if ( $self->print_gaf ) {
                $anno->print;
            }
            my $anno_check = $self->find( $anno->feature_id,
                $anno->cvterm_for_go, $anno->pub_for_dbref );
            my $rank = 0;
            if ($anno_check) {
                $rank = $anno_check->rank + 1;
            }
            my $fcvt
                = $schema->resultset('Sequence::FeatureCvterm')
                ->find_or_create(
                {   feature_id => $anno->feature_id,
                    cvterm_id  => $anno->cvterm_for_go,
                    pub_id     => $anno->pub_for_dbref,
                    rank       => $rank
                }
                );

            $fcvt->create_related(
                'feature_cvtermprops',
                {   type_id => $anno->cvterm_for_evidence_code,
                    value   => 1,
                    rank    => $rank
                }
            );

            if ( $anno->qualifier ) {
                $fcvt->create_related(
                    'feature_cvtermprops',
                    {   type_id => $gaf_manager->cvterm_qualifier,
                        value   => $anno->qualifier,
                        rank    => $rank
                    }
                );
            }

            if ( $anno->date ) {
                $fcvt->create_related(
                    'feature_cvtermprops',
                    {   type_id => $gaf_manager->cvterm_date,
                        value   => $anno->date,
                        rank    => $rank
                    }
                );
            }

            if ( $anno->with_from ) {
                $fcvt->create_related(
                    'feature_cvtermprops',
                    {   type_id => $gaf_manager->cvterm_with_from,
                        value   => $anno->with_from,
                        rank    => $rank
                    }
                );
            }

            if ( $anno->assigned_by ) {
                $fcvt->create_related(
                    'feature_cvtermprops',
                    {   type_id => $gaf_manager->cvterm_assigned_by,
                        value   => $anno->assigned_by,
                        rank    => $rank
                    }
                );
            }
        }
    }
    $guard->commit;
    $io->close;

    my $update_count
        = $schema->resultset('Sequence::FeatureCvterm')->search()->count;
    $logger->info( $update_count . " annotations inserted" );
}

sub transform {
    my ( $self, $schema ) = @_;
    my $fcvt_src = $schema->source('Sequence::FeatureCvtermprop');
    $fcvt_src->remove_column('value');
    $fcvt_src->add_column(
        'value' => {
            data_type   => 'clob',
            is_nullable => 1
        }
    );
    my $pub_src = $schema->source('Pub::Pub');
    $pub_src->remove_column('uniquename');
    $pub_src->add_column(
        'uniquename' => {
            data_type   => 'varchar2',
            is_nullable => 0
        }
    );
    my $syn_src = $schema->source('Cv::Cvtermsynonym');
    $syn_src->remove_column('synonym');
    $syn_src->add_column(
        'synonym_' => {
            data_type   => 'varchar2',
            is_nullable => 0
        }
    );
    return $schema;
}

sub find {
    my ( $self, $feature, $cvterm, $pub ) = @_;
    my $anno_check
        = $self->schema->resultset('Sequence::FeatureCvterm')
        ->search(
        { feature_id => $feature, cvterm_id => $cvterm, pub_id => $pub },
        { order_by => { -desc => 'rank' } } )->first;
    return $anno_check;
}

1;

package EBIQuery;

use LWP::UserAgent;
use Moose;

has 'ebi_base_url' => (
    is  => 'ro',
    isa => 'Str',
    default =>
        'http://www.ebi.ac.uk/QuickGO/GAnnotation?format=gaf&db=dictyBase&limit=-1',
    lazy => 1,
);

has 'ua' => (
    is      => 'ro',
    isa     => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
    lazy    => 1
);

sub query_ebi {
    my ($self) = @_;
    my $response = $self->ua->get( $self->ebi_base_url );
    $response->is_success || die "NO GAF retrieved from EBI";
    return $response->decoded_content;
}

1;

package GAFManager;

use Moose;

has 'logger' => (
    is  => 'rw',
    isa => 'Log::Log4perl::Logger'
);

has 'schema' => (
    is  => 'rw',
    isa => 'Bio::Chado::Schema',
);

has 'cvterm_date' => (
    is  => 'rw',
    isa => 'Int',
);

has 'cvterm_with_from' => (
    is  => 'rw',
    isa => 'Int',
);

has 'cvterm_assigned_by' => (
    is  => 'rw',
    isa => 'Int',
);

has 'cvterm_qualifier' => (
    is  => 'rw',
    isa => 'Int',
);

sub parse {
    my ( $self, $gaf ) = @_;
    my @annotations;
    my $io = IO::String->new();
    $io->open($gaf);
    while ( my $line = $io->getline ) {
        chomp($line);
        next if $line =~ /^!/x;

        my @row_vals = split( "\t", $line );
        my $anno = Annotation->new;
        if ( $self->schema ) {
            $anno->_schema( $self->schema );
        }
        if ( $self->logger ) {
            $anno->_logger( $self->logger );
        }
        $anno->db( $row_vals[0] );
        $anno->gene_id( $row_vals[1] );
        $anno->gene_symbol( $row_vals[2] );
        $anno->qualifier( $row_vals[3] );
        $anno->go_id( $row_vals[4] );
        $anno->db_ref( $row_vals[5] );
        $anno->evidence_code( $row_vals[6] );
        $anno->with_from( $row_vals[7] );
        $anno->aspect( $row_vals[8] );
        $anno->taxon( $row_vals[12] );
        $anno->date( $row_vals[13] );
        $anno->assigned_by( $row_vals[14] );

        if ( $anno->is_valid() ) {
            push( @annotations, $anno );
        }
    }
    return @annotations;
}

sub init {
    my ($self) = @_;
    my $qualifier_rs = $self->schema->resultset('Cv::Cvterm')
        ->search( { name => 'qualifier' } );
    $self->cvterm_qualifier( $qualifier_rs->first->cvterm_id );

    my $source_rs = $self->schema->resultset('Cv::Cvterm')
        ->search( { name => 'source' } );
    $self->cvterm_assigned_by( $source_rs->first->cvterm_id );

    my $with_rs = $self->schema->resultset('Cv::Cvterm')
        ->search( { name => 'with' } );
    $self->cvterm_with_from( $with_rs->first->cvterm_id );

    my $date_rs = $self->schema->resultset('Cv::Cvterm')
        ->search( { name => 'date' } );
    $self->cvterm_date( $date_rs->first->cvterm_id );
}

1;

package Annotation;

use Moose;
use MooseX::Attribute::Dependent;

has '_logger' => (
    is  => 'rw',
    isa => 'Log::Log4perl::Logger'
);

has '_schema' => (
    is  => 'rw',
    isa => 'Bio::Chado::Schema'
);

has 'db' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'dictyBase',
    lazy    => 1
);

has 'taxon' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'taxon:44689',
    lazy    => 1
);

has [qw/gene_id go_id db_ref evidence_code/] => (
    is  => 'rw',
    isa => 'Str',
);

has [qw/date with_from assigned_by qualifier aspect gene_symbol/] => (
    is  => 'rw',
    isa => 'Str',
);

has 'feature_id' => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $rs = $self->_schema->resultset('Sequence::Feature')->search(
            { 'dbxref.accession' => $self->gene_id, 'type.name' => 'gene' },
            { join => [qw/dbxref type/], select => 'feature_id' }
        );
        return $rs->first->feature_id;
    },
    lazy => 1
);

has 'pub_for_dbref' => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $id = $self->db_ref;
        $id =~ s/^[A-Z_]{4,7}://x;
        my $rs = $self->_schema->resultset('Pub::Pub')
            ->search( { uniquename => $id }, { select => 'pub_id' } );
        if ( $rs->count > 0 ) {
            return $rs->first->pub_id;
        }
        else {
            $self->_logger->warn(
                $self->db_ref . " does NOT exist (" . $self->gene_id . ")" );
            return 0;
        }
    },
    lazy       => 1,
    required   => 1,
    dependency => All ['db_ref']
);

has 'cvterm_for_go' => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $id = $self->go_id;
        $id =~ s/^GO://x;
        my $gors = $self->_schema->resultset('Cv::Cvterm')->search(
            { 'dbxref.accession' => $id, 'db.name' => 'GO' },
            {   join   => { dbxref => 'db' },
                cache  => 1,
                select => [qw/cvterm_id/]
            }
        );
        if ( $gors->count > 0 ) {
            return $gors->first->cvterm_id;
        }
        else {
            $self->_logger->warn( "Cvterm for "
                    . $self->go_id
                    . " does NOT exist ("
                    . $self->gene_id
                    . ")" );
            return 0;
        }
    },
    lazy       => 1,
    required   => 1,
    dependency => All ['go_id']
);

has 'cvterm_for_evidence_code' => (
    is      => 'ro',
    isa     => 'Int | Undef',
    default => sub {
        my ($self) = @_;
        my $rs = $self->_schema->resultset('Cv::Cv')
            ->search( { 'name' => { -like => 'evidence_code%' } } );
        my $syn_rs = $rs->first->cvterms->search_related(
            'cvtermsynonyms',
            {   'type.name' => { -in => [qw/EXACT RELATED BROAD/] },
                'cv.name'   => 'synonym_type'
            },
            { join => [ { 'type' => 'cv' } ], cache => 1 }
        );
        my $evrs = $syn_rs->search( { 'synonym_' => $self->evidence_code } );
        if ( $evrs->count > 0 ) {
            return $evrs->first->cvterm_id;
        }
        else {
            $self->_logger->warn( "Cvterm for "
                    . $self->evidence_code
                    . " does NOT exist ("
                    . $self->gene_id
                    . ")" );
            return 0;
        }
    },
    lazy       => 1,
    required   => 1,
    dependency => All ['evidence_code']
);

sub is_valid {
    my ($self) = @_;

    if (   !$self->cvterm_for_go == 0
        && !$self->cvterm_for_evidence_code == 0
        && !$self->pub_for_dbref == 0 )
    {
        return 1;
    }
    else {
        return 0;
    }
}

sub print {
    my ($self) = @_;
    my $row
        = $self->db . "\t"
        . $self->gene_id . "\t"
        . $self->gene_symbol . "\t"
        . $self->qualifier . "\t"
        . $self->go_id . "\t"
        . $self->db_ref . "\t"
        . $self->evidence_code . "\t"
        . $self->with_from . "\t"
        . $self->aspect . "\t"
        . $self->taxon . "\t"
        . $self->date . "\t"
        . $self->assigned_by . "\n";
    print $row;
}

1;

__END__

=head1 NAME

C<Modware::Load::Command::ebigaf2chado> - Update dicty Chado with GAF from EBI

=head1 VERSION

version 0.0.6

=head1 SYNOPSIS
 
	perl modware-load ebigaf2chado -c config.yaml --prune --file <go_annotations.gaf> 

=head1 REQUIRED ARGUMENTS

	-c, --configfile 		Config file with required arguments
	--file 				File with GO annotations in GAF format

=head1 DESCRIPTION

Prune all the existing annotations from dicty Chado. Query EBI using the web-service for annotations for each Gene ID.
Check if the link exists between feature and annotation; if yes, populate the retrieved data.

=cut
