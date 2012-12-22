
use autodie;
use strict;
use warnings;

package Modware::Load::Command::ebiGaf2dictyChado;

use Bio::Chado::Schema;
use IO::String;
use Moose;
use namespace::autoclean;

extends qw/Modware::Load::Chado/;

has 'prune' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    lazy          => 1,
    documentation => 'Delete all annotations before loading, default is OFF'
);

has 'print_gaf' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    lazy          => 1,
    documentation => 'Print GAF retrieved from EBI per gene ID'
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;
    $logger->info( "Loading config from " . $self->configfile );
    $logger->info( ref($self) );
    my $schema = $self->schema;
    if ( $self->prune ) {
        $logger->warn('Pruning all annotations.');
        my $prune_count
            = $schema->resultset('Sequence::FeatureCvterm')->search()->count;
        $schema->txn_do(
            sub { $schema->resultset('Sequence::FeatureCvterm')->delete_all }
        );
        $logger->info(
            "Done! with pruning. " . $prune_count . " records deleted." );
    }

    my $gaf_manager = GAFManager->new;
    $gaf_manager->schema($schema);
    $gaf_manager->logger($logger);

    $logger->info('Retrieving gene IDs from dictyBase');
    my $gene_rs = $gaf_manager->get_gene_ids();

    if ( $gene_rs->count == 0 ) {
        $logger->error('NO gene IDs retrieved');
        exit;
    }
    else {
        $logger->info( $gene_rs->count . " gene IDs retrieved" );
    }
    my $guard     = $self->schema->storage->txn_scope_guard;
    my $ebi_query = EBIQuery->new;
    while ( my $gene = $gene_rs->next ) {

        my $gaf         = $ebi_query->query_ebi( $gene->dbxref->accession );
        my @annotations = $gaf_manager->parse($gaf);

        foreach my $anno (@annotations) {

            if ( $self->print_gaf ) {
                $anno->print;
            }

            my $anno_check = $self->find( $gene->feature_id,
                $anno->cvterm_for_go, $anno->pub_for_dbref );
            my $rank = 0;
            if ($anno_check) {
                $rank = $anno_check->rank + 1;
            }
            my $fcvt
                = $schema->resultset('Sequence::FeatureCvterm')
                ->find_or_create(
                {   feature_id => $gene->feature_id,
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

            if ( $anno->qualifier ne '' ) {
                $fcvt->create_related(
                    'feature_cvtermprops',
                    {   type_id => $gaf_manager->cvterm_qualifier,
                        value   => $anno->qualifier,
                        rank    => $rank
                    }
                );
            }

            if ( $anno->date ne '' ) {
                $fcvt->create_related(
                    'feature_cvtermprops',
                    {   type_id => $gaf_manager->cvterm_date,
                        value   => $anno->date,
                        rank    => $rank
                    }
                );
            }

            if ( $anno->with_from ne '' ) {
                $fcvt->create_related(
                    'feature_cvtermprops',
                    {   type_id => $gaf_manager->cvterm_with_from,
                        value   => $anno->with_from,
                        rank    => $rank
                    }
                );
            }

            if ( $anno->assigned_by ne '' ) {
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

    my $update_count
        = $schema->resultset('Sequence::FeatureCvterm')->search()->count;
    $logger->info( $update_count
            . " annotations inserted for "
            . $gene_rs->count
            . " genes" );

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
use MooseX::Attribute::Dependent;

has 'ebi_base_url' => (
    is      => 'rw',
    isa     => 'Str',
    default => sub {
        my ($self) = @_;
        'http://www.ebi.ac.uk/QuickGO/GAnnotation?format='
            . $self->format . '&db='
            . $self->db
            . '&protein=';
    },
    lazy       => 1,
    dependency => All [ 'format', 'db' ]
);

has 'format' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'gaf',
    lazy    => 1
);

has 'db' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'dictyBase',
    lazy    => 1
);

has 'ua' => (
    is      => 'ro',
    isa     => 'LWP::UserAgent',
    default => sub { LWP::UserAgent->new },
    lazy    => 1
);

sub query_ebi {
    my ( $self, $gene_id ) = @_;
    my $response = $self->ua->get( $self->ebi_base_url . $gene_id );
    $response->is_success || die "NO GAF retrieved from EBI";
    return $response->decoded_content;
}

1;

package GAFManager;

use Moose;
use MooseX::Attribute::Dependent;

has 'logger' => (
    is  => 'rw',
    isa => 'Log::Log4perl::Logger'
);

has 'schema' => (
    is  => 'rw',
    isa => 'Bio::Chado::Schema',
);

has 'cvterm_date' => (
    is      => 'rw',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $date_rs = $self->schema->resultset('Cv::Cvterm')
            ->search( { name => 'date' } );
        return $date_rs->first->cvterm_id;
    },
    lazy       => 1,
    dependency => All ['schema']
);

has 'cvterm_with_from' => (
    is      => 'rw',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $with_rs = $self->schema->resultset('Cv::Cvterm')
            ->search( { name => 'with' } );
        return $with_rs->first->cvterm_id;
    },
    lazy       => 1,
    dependency => All ['schema']
);

has 'cvterm_assigned_by' => (
    is      => 'rw',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $source_rs = $self->schema->resultset('Cv::Cvterm')
            ->search( { name => 'source' } );
        return $source_rs->first->cvterm_id;
    },
    lazy       => 1,
    dependency => All ['schema']
);

has 'cvterm_qualifier' => (
    is      => 'rw',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $qualifier_rs = $self->schema->resultset('Cv::Cvterm')
            ->search( { name => 'qualifier' } );
        return $qualifier_rs->first->cvterm_id;
    },
    lazy       => 1,
    dependency => All ['schema']
);

sub get_gene_ids {
    my ($self) = @_;
    my $gene_rs = $self->schema->resultset('Sequence::Feature')->search(
        {   'type.name'            => 'gene',
            'organism.common_name' => 'dicty'
        },
        {   join     => [qw/type organism/],
            select   => [qw/feature_id uniquename type_id/],
            prefetch => 'dbxref',

            #rows     => 500
        }
    );
    return $gene_rs;
}

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

    #if ( scalar @annotations ) {
    #    $self->logger->info(
    #              scalar @annotations
    #            . " annotations parsed for "
    #            . $annotations[0]->gene_id );
    #}
    return @annotations;
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
    dependency => All [ 'db_ref', '_schema' ]
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
            { join => { dbxref => 'db' }, select => [qw/cvterm_id/] }
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
    dependency => All [ 'go_id', '_schema' ]
);

has 'cvterm_for_evidence_code' => (
    is      => 'ro',
    isa     => 'Int',
    default => sub {
        my ($self) = @_;
        my $evrs = $self->_schema->resultset('Cv::Cvterm')->search(
            {   'cv.name' => { -like => 'evidence_code%' },
                'cvtermsynonyms.synonym_' => $self->evidence_code
            },
            { join => [qw/cv cvtermsynonyms/], select => 'cvterm_id' }
        );
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
    dependency => All [ 'evidence_code', '_schema' ]
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

        #. $self->qualifier . "\t"
        . $self->go_id . "\t"
        . $self->db_ref . "\t"
        . $self->evidence_code . "\t"

        #. $self->with_from . "\t"
        . $self->aspect . "\t"

        #. $self->taxon . "\t"
        #. $self->date . "\t"
        #. $self->assigned_by
        . "\n";
    print $row;
}

1;

__END__

=head1 NAME

C<Modware::Load::Command::ebiGaf2dictyChado> - Update dicty Chado with GAF from EBI

=head1 VERSION

version 0.0.4

=head1 SYNOPSIS
 
	perl modware-load ebigaf2dictychado -c config.yaml --print_gaf

	perl modware-load ebigaf2dictychado -c config.yaml --prune 

=head1 REQUIRED ARGUMENTS

	-c, --configfile 		Config file with required arguments

=head1 DESCRIPTION

Prune all the existing annotations from dicty Chado. Query EBI using the web-service for annotations for each Gene ID.
Check if the link exists between feature and annotation; if yes, populate the retrieved data.

=cut
