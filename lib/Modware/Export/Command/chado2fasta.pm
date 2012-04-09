package Modware::Export::Command::chado2fasta;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
extends qw/Modware::Export::Chado/;

# Module implementation
#

has 'exclude_mitochondrial' => (
    is          => 'rw',
    isa         => 'Bool',
    traits      => [qw/Getopt/],
    lazy        => 1,
    cmd_aliases => 'only_nuclear',
    default     => 0,
    documentation =>
        'Exclude mitochondrial genome(only nuclear),  default is false'
);

has 'only_mitochondrial' => (
    is          => 'rw',
    isa         => 'Bool',
    traits      => [qw/Getopt/],
    lazy        => 1,
    cmd_aliases => 'exclude_nuclear',
    default     => 0,
    documentation =>
        'Dump mitochondrial genome(exclude nuclear),  default is false'
        . 'It works only if the SO term *mitochondrial_DNA* is being set as feature property'
        . 'for the reference feature'
);

has 'feature_name' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    documentation =>
        'Output feature name instead of sequence id in the fasta header,  default is off.'
);

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
        'all_types_of_sequence'      => 'keys',
        'register_type_for_sequence' => 'set',
        'get_coderef_for_sequence'   => 'get',
        'has_type_for_sequence'      => 'defined'
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

override 'execute' => sub {
    my ($self) = @_;
    my $logger = $self->logger;

    if ( !$self->has_species ) {
        if ( !$self->has_genus ) {
            if ( !$self->has_organism ) {
                $logger->log_fatal(
                    "at least species,  genus or common_name has to be set");
            }
        }
    }

    my $query;
    $query->{species}     = $self->species  if $self->has_species;
    $query->{genus}       = $self->genus    if $self->has_genus;
    $query->{common_name} = $self->organism if $self->has_organism;

    my $org_rs = $self->schema->resultset('Organism::Organism')->search(
        $query,
        {   select => [
                qw/species genus
                    common_name organism_id/
            ]
        }
    );

    if ( !$org_rs->count ) {
        $logger->log_fatal(
            "Could not find given organism  in chado database");
    }

    my $type   = $self->type;
    # coderef for nuclear dumps only
    if ( $self->exclude_mitochondrial ) {
        my $source = $self->schema->source('Sequence::Feature');

        # add the relationship for LEFT JOIN
        if ( !$source->has_relationship('reference_featurelocs') ) {
            $source->add_relationship(
                'reference_featurelocs',
                'Sequence::Featureloc',
                { 'foreign.feature_id' => 'self.feature_id' },
                { join_type            => 'LEFT' }
            );
        }

        # reference feature testing
        $source->add_relationship(
            'reference_featurerels',
            'Sequence::FeatureRelationship',
            { 'foreign.subject_id' => 'self.feature_id' },
            { join_type            => 'LEFT' }
        );

        $self->register_type2feature_handler(
            $_,
            sub {
                $self->get_nuclear_type2feature(@_);
            }
            )
            for qw/supercontig chromosome
            ncRNA rRNA tRNA mRNA/;
        $self->register_type2feature_handler( 'polypeptide',
            sub { $self->get_polypeptide_feature(@_) } );
        $self->register_type_for_sequence( 'polypeptide',
            sub { $self->dump_polypeptide_sequence(@_) } );
    }

    # coderef for mito dumps only
    if ( $self->only_mitochondrial ) {
        my $source = $self->schema->source('Sequence::Feature');
        if ( !$source->has_relationship('reference_featurelocs') ) {
            $source->add_relationship(
                'reference_featurelocs',
                'Sequence::Featureloc',
                { 'foreign.feature_id' => 'self.feature_id' },
                { join_type            => 'LEFT' }
            );
        }
        $self->register_type2feature_handler(
            $_,
            sub {
                $self->get_mito_type2feature(@_);
            }
            )
            for qw/supercontig chromosome
            gene ncRNA rRNA tRNA mRNA/;
        $self->register_type2feature_handler( 'polypeptide',
            sub { $self->get_polypeptide_feature(@_) } );
        $self->register_type_for_sequence( 'polypeptide',
            sub { $self->dump_polypeptide_sequence(@_) } );
    }

    if ( $self->has_type2feature_handler( $self->type ) ) {
        my $rs = $self->get_type2feature_coderef( $self->type )
            ->( $org_rs, $self->type, $self->gff_source );
        $self->get_coderef_for_sequence( $self->type )
            ->( $rs, $self->output_handler );
    }
    else {
        $self->logger->log_fatal(
            "feature $type is not supported for dumping sequence");
    }
    $self->output_handler->close;
};

sub get_mito_type2feature {
    my ( $self, $dbrow, $type, $source ) = @_;
    my $ref_join = {
        join => [
            'reference_featurelocs', { 'featureprops' => { 'type' => 'cv' } }
        ],
        cache => 1
    };
    my $ref_query = {
        'reference_featurelocs.srcfeature_id' => undef,
        'type.name'                           => 'mitochondrial_DNA',
        'cv.name'                             => 'sequence'
    };
    my $join
        = { join => [qw/type featureloc_features/], prefetch => 'dbxref' };
    my $query = { 'type.name' => $type };

    if ($source) {
        push @{ $ref_join->{join} },
            { 'feature_dbxrefs' => { 'dbxref' => 'db' } };
        push @{ $join->{join} },
            { 'feature_dbxrefs' => { 'dbxref' => 'db' } };
        $ref_query->{'db.name'} = $source;
        $query->{'db.name'}     = $source;
    }

    # get SO type of reference feature
    my $ref_rs = $dbrow->search_related( 'features', $ref_query, $ref_join );
    if ( $ref_rs->first->type->name eq $type ) {
        $ref_rs->reset;
        return $ref_rs;
    }

  # children features should map to one of the mitochondrial reference feature
    $query->{'featureloc_features.srcfeature_id'} = [ map { $_->feature_id }
            $ref_rs->search( {}, { select => 'feature_id' } ) ];
    my $rs = $dbrow->search_related( 'features', $query, $join );
    $self->logger->log_fatal(
        "no mitochondrial feature $type found in the database")
        if !$rs->count;
    return $rs;
}

sub get_nuclear_type2feature {
    my ( $self, $dbrow, $type, $source ) = @_;
    my $mito_ref_join = {
        join => [
            'reference_featurelocs', { 'featureprops' => { 'type' => 'cv' } }
        ],
        cache => 1
    };
    my $mito_ref_query = {
        'reference_featurelocs.srcfeature_id' => undef,
        'type.name'                           => 'mitochondrial_DNA',
        'cv.name'                             => 'sequence'
    };
    my $join
        = { join => [qw/type featureloc_features/], prefetch => 'dbxref' };
    my $query = { 'type.name' => $type };

    if ($source) {
        push @{ $mito_ref_join->{join} },
            { 'feature_dbxrefs' => { 'dbxref' => 'db' } };
        push @{ $join->{join} },
            { 'feature_dbxrefs' => { 'dbxref' => 'db' } };
        $mito_ref_query->{'db.name'} = $source;
        $query->{'db.name'}          = $source;
    }

    # get SO type of nuclear(not mitochondrial) reference feature
    my $mito_rs = $dbrow->search_related( 'features', $mito_ref_query,
        $mito_ref_join );
    my $ref_rs = $dbrow->search_related(
        'features',
        {   'reference_featurelocs.srcfeature_id' => undef,
            'reference_featurerels.object_id'     => undef,
            'features.feature_id' =>
                { -not_in => $mito_rs->get_column('feature_id')->as_query }
        },
        {   join  => [ 'reference_featurelocs', 'reference_featurerels' ],
            cache => 1
        }
    );

    my $ref_type = $ref_rs->first->type->name;
    if ( $ref_rs->first->type->name eq $type )
    {    #reference feature needs to be retrieved
        $ref_rs->reset;
        return $ref_rs;
    }

    # children features should map to one of the nuclear reference feature
    $query->{'featureloc_features.srcfeature_id'} = {
        'in',
        [   map { $_->feature_id }
                $ref_rs->search( {}, { select => 'feature_id' } )
        ]
    };
    my $rs = $dbrow->search_related( 'features', $query, $join );
    $self->logger->log_fatal("no nuclear feature $type found in the database")
        if !$rs->count;
    return $rs;
}

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
    return $self->get_type2feature_coderef('mRNA')
        ->( $dbrow, 'mRNA', $source );
}

sub get_polypeptide_feature {
    my ( $self, $dbrow, $type, $source ) = @_;
    return $self->get_type2feature_coderef('mRNA')
        ->( $dbrow, 'mRNA', $source );
}

sub dump_sequence {
    my ( $self, $rs, $output ) = @_;
    my $logger = $self->logger;
    my $method = $self->feature_name ? '_chado_name' : '_chado_feature_id';
    while ( my $dbrow = $rs->next ) {
        my $id = $self->$method($dbrow);
        if ( !$id ) {
            $logger->log( "Unable to fetch name for feature: ",
                $dbrow->uniquename );
            return;
        }
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
    my $method = $self->feature_name ? '_chado_name' : '_chado_feature_id';
    while ( my $dbrow = $rs->next ) {
        my $id = $self->$method($dbrow);
        if ( !$id ) {
            $self->logger->log( "Unable to fetch name for feature: ",
                $dbrow->uniquename );
            return;
        }
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

sub dump_polypeptide_sequence {
    my ( $self, $rs, $output ) = @_;

    # it is a mRNA resultset object
    my $poly_rs = $rs->search_related(
        'feature_relationship_objects',
        { 'type_2.name' => 'derives_from' },
        { join        => 'type' }
        )->search_related(
        'subject',
        { 'type_3.name' => 'polypeptide' },
        { join          => 'type', prefetch => 'dbxref' }
        );
    $self->dump_sequence( $poly_rs, $output );
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

Modware::Export::Command::chado2fasta - Export fasta sequence file from chado database

