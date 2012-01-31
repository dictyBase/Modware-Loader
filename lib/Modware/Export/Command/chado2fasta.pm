package Modware::Export::Command::chado2fasta;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
extends qw/Modware::Export::Chado/;

# Module implementation
#

has '_type2retrieve' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => {
        'all_type2features'             => 'keys',
        'get_type2feature_coderef'      => 'get',
        'register_type2feature_handler' => 'set',
        'has_type2feature_handler'      => 'defined'
    },
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $hashref;
        $hashref->{$_} = sub { $self->get_type2feature(@_) }
            for qw/supercontig chromosome
            gene ncRNA rRNA tRNA mRNA polypeptide/;
        $hashref->{cds} = sub { $self->get_cds(@_) };
        return $hashref;
    }
);

has '_dump_sequence' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    handles => {
        'all_typesof_sequence'    => 'keys',
        'add_typefor_sequence'    => 'set',
        'get_codereffor_sequence' => 'get',
        'has_typefor_sequence'    => 'defined'
    },
    default => sub {
        my ($self) = @_;
        my $hashref;
        $hashref->{$_} = sub { $self->dump_sequence(@_) }
            for qw/supercontig chromosome
            polypeptide/;
        $hashref->{$_} = sub { $self->infer_and_dump_sequence(@_) }
            for qw/gene mRNA ncRNA
            rRNA tRNA/;
        $hashref->{cds} = sub { $self->dump_cds_sequence(@_) };
        return $hashref;
    }
);

has 'type' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'type of feature whose sequences will be dumped'
);

has 'gff_source' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'GFF source(column 2) to which the feature belong to,  optional'
);

augment 'execute' => sub {
    my ($self) = @_;
    my $dbrow  = $self->_organism_result;
    my $type   = $self->type;
    if ( $self->has_type2feature_handler( $self->type ) ) {
        my $rs = $self->get_type2feature_coderef( $self->type )
            ->( $dbrow, $self->type, $self->gff_source );
        $self->get_codereffor_sequence( $self->type )
            ->( $rs, $self->output_handler );
    }
    else {
        $self->logger->log_fatal(
            "feature $type is not supported for dumping sequence");
    }
    $self->output_handler->close;
};

sub get_type2feature {
    my ( $self, $dbrow, $type, $source ) = @_;
    my $rs;
    if ($source) {
        $rs = $dbrow->search_related(
            'features',
            {   'type.name'        => $type,
                'dbxref.accession' => $source,
                'db.name'          => 'GFF_source'
            },
            {   join =>
                    [ 'type', { 'feature_dbxrefs' => { 'dbxref' => 'db' } } ],
                prefetch => 'dbxref'
            }
        );
    }
    else {
        $rs = $dbrow->search_related(
            'features',
            { 'type.name' => $type },
            {   join     => 'type',
                prefetch => 'dbxref'
            }
        );
    }
    $self->logger->log_fatal("no feature $type found in the database")
        if !$rs->count;
    return $rs;
}

sub get_cds {
    my ( $self, $dbrow, $type, $source ) = @_;
    return $self->get_type2feature( $dbrow, 'mRNA', $source );
}

sub dump_sequence {
    my ( $self, $rs, $output ) = @_;
    my $logger = $self->logger;
    while ( my $dbrow = $rs->next ) {
        my $id = $self->_chado_feature_id($dbrow);
        if ( my $seq = $dbrow->residues ) {
            $seq =~ s/(\S{1,60})/$1\n/g;
            $output->print( ">$id\n", $seq );
        }
        else {
            $logger->log("No sequences found for $id");
        }
    }
}

sub infer_and_dump_sequence {
    my ( $self, $rs, $output ) = @_;
    while ( my $dbrow = $rs->next ) {
        my $id  = $self->_chado_feature_id($dbrow);
        my $seq = $dbrow->residues;
        if ( !$seq ) {
            my $floc   = $dbrow->featureloc_features->first;
            my $start  = $floc->fmin + 1;
            my $end    = $floc->fmax;
            my $seqlen = $end - $start + 1;
            $seq = $floc->search_related(
                'srcfeature',
                {},
                {   select =>
                        [ \"SUBSTR(srcfeature.residues,  $start, $seqlen)" ],
                    as => 'fseq'
                }
            )->first->get_column('fseq');

            if ( $floc->strand == -1 ) {    ## reverse complement
                $seq = join( '', reverse( split '', $seq ) );
                $seq =~ tr/ATGC/TACG/;
            }
        }

        $seq =~ s/(\S{1,60})/$1\n/g;
        $output->print( ">$id\n", $seq );
    }
}

sub dump_cds_sequence {
    my ( $self, $rs, $output ) = @_;
    while ( my $dbrow = $rs->next ) {
        my $exon_rs = $dbrow->search_related(
            'feature_relationship_objects',
            { 'type.name' => 'part_of' },
            { join        => 'type' }
            )->search_related(
            'subject',
            { 'type_2.name' => 'exon' },
            { join          => 'type' }
            )
            ->search_related( 'featureloc_features', {},
            { 'order_by' => { -asc => 'fmin' } } );

        my $seq;
        for my $erow ( $exon_rs->all ) {
            my $start  = $erow->fmin + 1;
            my $end    = $erow->fmax;
            my $seqlen = $end - $start + 1;
            $seq .= $erow->search_related(
                'srcfeature',
                {},
                {   select => [ \"SUBSTR(me.residues,  $start, $seqlen)" ],
                    as     => 'fseq'
                }
            )->first->get_column('fseq');
        }
        if ( $dbrow->featureloc_features->first->strand == -1 ) {
            $seq = join( '', reverse( split '', $seq ) );
            $seq =~ tr/ATGC/TACG/;
        }
        $seq =~ s/(\S{1,60})/$1\n/g;
        my $id = $self->_chado_feature_id($dbrow);
        $output->print( ">$id\n", $seq );
    }
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Export fasta sequence file from chado database

