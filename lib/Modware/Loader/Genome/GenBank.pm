package Modware::Loader::Genome::GenBank;
use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;
use Bio::SeqIO;
use Digest::MD5 qw/md5_hex/;
use Storable qw/dclone/;
use Bio::SeqFeature::Gene::Exon;
use Bio::SeqFeature::Gene::Transcript;
use Modware::Collection::FeatureStack;
use Modware::MOD::Registry;

has 'pubid' => (
    is  => 'rw',
    isa => 'Str',
);

has '_feat2linkstack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $feats;
        push @$feats, qw/gene mRNA tRNA ncRNA rRNA polypeptide/;
        return $feats;
    },
    handles => {
        'all_feat2link' => 'elements',
        'add_feat2link' => 'push',
        'has_feat2link' => 'count'
    }
);

has 'reference_type' => ( is => 'rw', isa => 'Str' );

has 'input' => (
    is      => 'rw',
    isa     => 'IO::Handle',
    trigger => sub {
        my ( $self, $handler ) = @_;
        $self->seqio(
            Bio::SeqIO->new( -fh => $handler, -format => 'genbank' ) );
    }
);

has 'seqio' => (
    is  => 'rw',
    isa => 'Bio::SeqIO'
);

has 'schema' =>
    ( is => 'rw', isa => 'Bio::Chado::Schema', predicate => 'has_schema' );

has 'id_prefix' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $dbrow = $self->organism_row;
        my $prefix
            = substr( $dbrow->genus, 0, 1 ) . substr( $dbrow->species, 0, 1 );
        return uc $prefix;
    }
);

has 'logger' => (
    is  => 'rw',
    isa => 'Object'
);

has 'organism_row' => (
    is        => 'rw',
    isa       => 'DBIx::Class::Row',
    predicate => 'has_organism_row'
);

has 'genome_source' => (
    is      => 'rw',
    isa     => 'Str',
    trigger => sub {
        my ( $self, $source ) = @_;
        if ( $self->has_schema ) {
            my $row = $self->schema->resultset('General::Db')
                ->find_or_create( { name => $source } );
            $row->update(
                {   urlprefix => 'http://ncbi.nlm.nih.gov/nuccore/',
                    'url'     => 'http://ncbi.nlm.nih.gov/genbank/'
                }
            );
            $self->genome_dbrow($row);
        }
    }
);

has 'genome_dbrow' => (
    is  => 'rw',
    isa => 'DBIx::Class::Row'
);

has 'mod_dbrow' => (
    is  => 'rw',
    isa => 'DBIx::Class::Row'
);

has 'chado_dbrow' => (
    is  => 'rw',
    isa => 'DBIx::Class::Row'
);

has '_cvterm_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_cvterm_row    => 'set',
        get_cvterm_row    => 'get',
        delete_cvterm_row => 'delete',
        has_cvterm_row    => 'defined'
    }
);

has '_dbxref_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_dbxref_row    => 'set',
        get_dbxref_row    => 'get',
        delete_dbxref_row => 'delete',
        has_dbxref_row    => 'defined'
    }
);

has '_dbrow' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_dbrow => 'set',
        get_dbrow => 'get',
        has_dbrow => 'defined'
    }
);

has '_scaffold_cache' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub {
        return {};
    },
    lazy    => 1,
    handles => {
        add_to_scaffold_cache       => 'set',
        get_from_scaffold_cache     => 'get',
        all_from_scaffold_cache     => 'keys',
        all_ids_from_scaffold_cache => 'values',
        has_scaffold_cache          => 'defined'
    }
);

has '_feature_collection' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub { {} },
    handles => {
        cache_feature          => 'set',
        is_feature_in_cache    => 'defined',
        get_feature_from_cache => 'get',
        clear_feature_cache    => 'clear'
    }
);

has 'mod_registry' => (
    is      => 'rw',
    isa     => 'Modware::MOD::Registry',
    lazy    => 1,
    default => sub {
        return Modware::MOD::Registry->new;
    }
);

has '_tags_to_filter' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub {
        { translation => 1, db_xref => 1 };
    },
    handles => {
        add_tag_to_filter => 'set',
        is_tag_to_filter  => 'defined'
    }
);

has '_allowed_feature' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => { is_feature_storable => 'defined' },
    lazy    => 1,
    default => sub {
        return {
            'gene'  => 1,
            'mRNA'  => 1,
            'exon'  => 1,
            'CDS'   => 1,
            'tRNA'  => 1,
            'ncRNA' => 1,
            'rRNA'  => 1
        };
    }
);

has 'is_mitochondrial_genome' => (
    is      => 'rw',
    isa     => 'Bool',
    lazy    => 1,
    default => 0,
    traits  => [qw/Bool/],
    handles => {
        'set_mitochondrial_genome'   => 'set',
        'unset_mitochondrial_genome' => 'unset',
    }
);

has 'feature_loader_method' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'load_canonical_features'
);

sub mod_source {
    my ( $self, $source ) = @_;
    my $registry = $self->mod_registry;
    my $schema   = $self->schema;
    my $dbrow    = $schema->resultset('General::Db')
        ->find_or_create( { 'name' => $source } );
    $dbrow->update(
        {   'urlprefix' => $registry->get_url_prefix($source),
            url         => $registry->get_url($source),
            description => $registry->get_description($source)
        }
    );
    $self->mod_dbrow($dbrow);
}

sub transform_schema {
    my ($self) = @_;
    if ( $self->has_schema ) {
        my $source = $self->schema->source('Organism::Organism');
        $source->remove_column('comment');
        $source->add_column(
            'comment_' => {
                data_type   => 'text',
                is_nullable => 1
            }
        );
    }
}

sub find_or_create_organism {
    my ( $self, $seq ) = @_;
    my $schema = $self->schema;
    my $logger = $self->logger;

    my ($feat) = grep { $_->primary_tag eq 'source' } $seq->get_SeqFeatures;
    my ($strain) = $feat->get_tag_values('strain')
        if $feat->has_tag('strain');

    # -- check for mitochondrial genome
    if ( $feat->has_tag('organelle') ) {
        my ($organelle) = $feat->get_tag_values('organelle');
        $self->set_mitochondrial_genome;
        $self->feature_loader_method('load_mitochondrial_features');
    }

    ## setting species,  genus,  common name and abbreviation
    my $species
        = $strain
        ? $seq->species->species . ' ' . $strain
        : $seq->species->species;
    my $genus        = $seq->species->genus;
    my $common_name  = $seq->species->species;
    my $abbreviation = substr( $genus, 0, 1 ) . '.' . $seq->species->species;

    my $org_row = $schema->resultset('Organism::Organism')
        ->find( { genus => $genus, species => $species } );

    if ($org_row) {
        $self->organism_row($org_row);
        $logger->info(
            "organism $genus $species $common_name is already present in database"
        );
        return;
    }

    my $row = $schema->resultset('Organism::Organism')->create(
        {   genus        => $genus,
            species      => $species,
            abbreviation => $abbreviation,
            common_name  => $common_name,
        }
    );
    $self->organism_row($row);
    $logger->info(
        "Created organism $genus $species $common_name in database");
}

sub add_genome_tag {
    my ($self) = @_;
    my $cvterm = $self->_get_genome_tag_cvterm;
    my $schema = $self->schema;
    my $row    = $self->organism_row->search_related(
        'organismprops',
        { type_id => $cvterm->cvterm_id },
        { rows    => 1 }
    )->single;

    if ($row) {
        $self->logger->info(
            "genome ",
            $self->organism_row->abbreviation,
            " is already tagged: upgrading version"
        );
        $row->update( { value => $row->value + '1.0' } );
        return;
    }

    $self->organism_row->create_related(
        'organismprops',
        {   value   => '1.0',
            type_id => $cvterm->cvterm_id
        }
    );

    $self->logger->info(
        "genome ",
        $self->organism_row->abbreviation,
        " is tagged with version 1.0"
    );
}

sub _get_genome_tag_cvterm {
    my ($self) = @_;
    my $schema = $self->schema;
    my $row    = $schema->resultset('Cv::Cvterm')->search(
        {   'cv.name' => 'genome_properties',
            'me.name' => 'loaded_genome'
        },
        { join => 'cv', rows => 1 }
    )->single;
    if ( !$row ) {    ## -- need to create the cvterm
        $row = $self->schema->resultset('Cv::Cvterm')->create(
            {   'name'     => 'loaded_genome',
                definition => 'Genome loaded in chado database',
                'cv_id'    => $schema->resultset('Cv::Cv')
                    ->find_or_create( { 'name' => 'genome_properties' } )
                    ->cv_id,
                'dbxref' => {
                    'accession' => 'genome_properties:loaded_genome',
                    'db_id'     => $schema->resultset('General::Db')
                        ->find_or_create( { name => 'null' } )->db_id
                },
            }
        );
    }
    return $row;
}

sub load_scaffold {
    my ($self) = @_;
    my $schema = $self->schema;
    my $seqio  = $self->seqio;

SCAFFOLD:
    while ( my $seq = $seqio->next_seq ) {
        if ( !$self->has_organism_row ) {
            $self->find_or_create_organism($seq);
        }

        if ( $self->has_scaffold_cache( $seq->display_id ) ) {
            $self->logger->warn( $seq->display_id,
                ' already present skipped loading of any feature annotations'
            );
            next SCAFFOLD;
        }
        my $accession = $self->id_prefix . $self->next_feature_id();
        my $row       = $schema->resultset('Sequence::Feature')->create(
            {   organism_id => $self->organism_row->organism_id,
                uniquename  => $seq->display_id,
                name        => $seq->display_id,
                type_id     => $self->find_cvterm_id(
                    $self->reference_type, 'sequence'
                ),
                residues    => $seq->seq,
                seqlen      => $seq->length,
                md5checksum => md5_hex( $seq->seq ),
                dbxref      => {
                    accession   => $accession,
                    db_id       => $self->mod_dbrow->db_id,
                    version     => $seq->seq_version,
                    description => $seq->desc
                },
                feature_dbxrefs => [
                    {   dbxref_id =>
                            $self->get_dbxref_row('GenBank')->dbxref_id
                    }
                ],
                featureprops => [
                    {   value   => 1,
                        type_id => $self->find_cvterm_id(
                            $self->is_mitochondrial_genome
                            ? 'mitochondrial_DNA'
                            : 'nuclear_sequence',
                            'sequence'
                        )
                    }
                ]
            }
        );

        $self->add_to_scaffold_cache( $seq->display_id, $row->feature_id );
        $self->logger->debug( "inserted scaffold genome id:",
            $accession, " genbank id:", $seq->display_id );
        $self->dispatch_to_feature_loader(
            method => $self->feature_loader_method,
            seq    => $seq,
            dbrow  => $row
        );
    }

    # could store feature description in featureprop for backward compat.
}

sub dispatch_to_feature_loader {
    my ( $self, %arg ) = @_;
    if ( !$self->can( $arg{method} ) ) {
        $self->logdie("cannot dispatch to $arg{method}");
    }
    my $method = $arg{method};
    $self->$method( $arg{seq}, $arg{dbrow} );
}

sub load_canonical_features {
    my ( $self, $seq, $row ) = @_;
    my $feat_stack = Modware::Collection::FeatureStack->new;
    $feat_stack->src_row($row);

FEAT:
    for my $feat ( $seq->get_SeqFeatures ) {
        my $tag = $feat->primary_tag;

        if ( $tag eq 'gene' ) {
            if ( $feat_stack->has_gene ) {
                $self->load_gene($feat_stack);
                $feat_stack->delete_all_features;
            }
            $feat_stack->gene($feat);
            next FEAT;
        }

        if ( $tag =~ /RNA$/ ) {
            $feat_stack->add_transcript($feat);
            next FEAT;
        }

        if ( $tag eq 'CDS' ) {
            $feat_stack->add_polypeptide($feat);
        }
    }

    if ( $feat_stack->has_gene ) {
        $self->load_gene($feat_stack);
        $feat_stack->delete_all_features;
    }
    $feat_stack->clear_src_row;
}

sub load_mitochondrial_features {
    my ( $self, $seq, $row ) = @_;
    my $feat_stack = Modware::Collection::FeatureStack->new;
    $feat_stack->src_row($row);

FEAT:
    for my $feat ( $seq->get_SeqFeatures ) {
        my $tag = $feat->primary_tag;

        if ( $tag eq 'gene' ) {
            if ( $feat_stack->has_gene ) {
                $self->load_gene($feat_stack);
                $feat_stack->delete_all_features;
            }
            $feat_stack->gene($feat);
            next FEAT;
        }

        if ( $tag =~ /RNA$/ ) {
            $feat_stack->add_transcript($feat);
            next FEAT;
        }

        if ( $tag eq 'CDS' ) {
            my $clone = dclone($feat);
            $clone->primary_tag('mRNA');
            $clone->strand( $feat_stack->gene->strand );
            $feat_stack->add_transcript($clone);
            $feat_stack->add_polypeptide($feat);
        }
    }

    if ( $feat_stack->has_gene ) {
        $self->load_gene($feat_stack);
        $feat_stack->delete_all_features;
    }
    $feat_stack->clear_src_row;
}

sub load_gene {
    my ( $self, $stack ) = @_;
    my $gene = $stack->gene;

    if ( !$gene->has_tag('gene') ) {
        if ( !$gene->has_tag('locus_tag') ) {
            $self->logger->logdie(
                "cannot load gene: *gene* or *locus_tag* do not exist");
        }
    }

    my ($uniquename)
        = $gene->has_tag('locus_tag')
        ? $gene->get_tag_values('locus_tag')
        : $gene->get_tag_values('gene');
    my $name;
    if ( $gene->has_tag('gene') ) {
        ($name) = $gene->get_tag_values('gene');
    }
    else {
        $name = $uniquename;
    }
    my $accession = $self->id_prefix . '_G' . $self->next_feature_id;

    my $gene_hash = {
        organism_id => $self->organism_row->organism_id,
        uniquename  => $uniquename,
        name        => $name,
        type_id     => $self->find_cvterm_id( 'gene', 'sequence' ),
        residues    => $gene->seq->seq,
        md5checksum => md5_hex( $gene->seq->seq ),
        seqlen      => $gene->seq->length,
        is_analysis => 1,
        dbxref      => {
            accession => $accession,
            db_id     => $self->mod_dbrow->db_id,
        },
        feature_dbxrefs =>
            [ { dbxref_id => $self->get_dbxref_row('GenBank')->dbxref_id } ]
    };

    ## -- maps gb tags to chado feature property
    $self->add_featureprops( $gene, $gene_hash );
    $self->add_dbxrefs( $gene, $gene_hash );

    ## -- location in reference feature
    $gene_hash->{featureloc_features} = [
        {   fmin          => $gene->start - 1,
            fmax          => $gene->end,
            strand        => $gene->strand,
            srcfeature_id => $stack->src_row->feature_id
        }
    ];

    ## -- relationship with parent feature
    $gene_hash->{feature_relationship_subjects} = [
        {   object_id => $stack->src_row->feature_id,
            type_id   => $self->find_cvterm_id( 'part_of', 'relationship' )
        }
    ];

    my $gene_row
        = $self->schema->resultset('Sequence::Feature')->create($gene_hash);

    $self->logger->info( "loaded gene $accession ", $gene_row->uniquename );

    $stack->gene_row($gene_row);
    $self->load_transcript($stack);
}

sub load_transcript {
    my ( $self, $stack ) = @_;
    for my $i ( 0 .. $stack->num_of_transcripts - 1 ) {
        my $trans = $stack->get_transcript($i);

        my $accession = $self->id_prefix . $self->next_feature_id;
        my $uniquename;
        if ( $trans->has_tag('locus_tag') ) {
            ($uniquename) = $trans->get_tag_values('locus_tag');
            $uniquename .= '.t' . sprintf( "%02d", $i );
        }
        else {
            $uniquename = $accession;
        }

        my $trans_hash = {
            organism_id => $self->organism_row->organism_id,
            uniquename  => $uniquename,
            name        => $uniquename,
            type_id =>
                $self->find_cvterm_id( $trans->primary_tag, 'sequence' ),
            is_analysis => 1,
            dbxref      => {
                accession => $accession,
                db_id     => $self->mod_dbrow->db_id,
            },
            feature_dbxrefs => [
                { dbxref_id => $self->get_dbxref_row('GenBank')->dbxref_id }
            ]
        };

        my $tseq = $trans->spliced_seq ? $trans->spliced_seq : $trans->seq;
        if ($tseq) {
            $trans_hash->{residues}    = $tseq->seq;
            $trans_hash->{md5checksum} = md5_hex( $tseq->seq );
            $trans_hash->{seqlen}      = $tseq->length;
        }

        $self->add_featureprops( $trans, $trans_hash );
        $self->add_dbxrefs( $trans, $trans_hash );

        ## -- location in reference feature
        $trans_hash->{featureloc_features} = [
            {   fmin          => $trans->start - 1,
                fmax          => $trans->end,
                strand        => $trans->strand,
                srcfeature_id => $stack->src_row->feature_id
            }
        ];

        ## -- relationship with parent feature
        $trans_hash->{feature_relationship_subjects} = [
            {   object_id => $stack->gene_row->feature_id,
                type_id => $self->find_cvterm_id( 'part_of', 'relationship' )
            }
        ];

        my $trans_row = $self->schema->resultset('Sequence::Feature')
            ->create($trans_hash);

        $self->logger->info( "loaded transcript ", $trans_row->uniquename );

        $stack->transcript_row($trans_row);
        $stack->feature_position($i);
        $self->load_exon($stack);

        if ( $stack->has_polypeptide ) {    ## -- coding transcript
            $self->load_polypeptide($stack);
        }
    }
}

sub load_exon {
    my ( $self, $stack ) = @_;
    my $trans = $stack->get_transcript( $stack->feature_position );

    for my $loc ( $trans->location->each_Location ) {

        my $feat_id   = $self->next_feature_id;
        my $accession = $self->id_prefix . $feat_id;
        my $exon_hash = {
            organism_id => $self->organism_row->organism_id,
            uniquename  => 'auto' . $feat_id,
            name        => 'exon-auto' . $feat_id,
            type_id     => $self->find_cvterm_id( 'exon', 'sequence' ),
            is_analysis => 1,
            dbxref      => {
                accession => $accession,
                db_id     => $self->mod_dbrow->db_id,
            },
            feature_dbxrefs => [
                { dbxref_id => $self->get_dbxref_row('GenBank')->dbxref_id }
            ]
        };

        ## -- location in reference feature
        $exon_hash->{featureloc_features} = [
            {   fmin          => $loc->start - 1,
                fmax          => $loc->end,
                strand        => $trans->strand,
                srcfeature_id => $stack->src_row->feature_id
            }
        ];

        ## -- relationship with parent feature
        $exon_hash->{feature_relationship_subjects} = [
            {   object_id => $stack->transcript_row->feature_id,
                type_id => $self->find_cvterm_id( 'part_of', 'relationship' )
            }
        ];

        my $exon_row = $self->schema->resultset('Sequence::Feature')
            ->create($exon_hash);

        $self->logger->info( "loaded exon ", $exon_row->uniquename );
    }
}

sub load_polypeptide {
    my ( $self, $stack ) = @_;

    my $pos  = $stack->feature_position;
    my $poly = $stack->get_polypeptide($pos);

    ## -- getting the sequence
    ## -- It looks for translation tag otherwise compute it from the transcript
    my $peptide;
    if ( my ($val) = $poly->get_tag_values('translation') ) {
        $peptide = $val;
    }
    else {
        $peptide
            = $self->calcuate_polypetide_seq( $self->get_transcript($pos) );
    }

    my $accession = $self->id_prefix . $self->next_feature_id;
    my $uniquename;
    if ( $poly->has_tag('locus_tag') ) {
        ($uniquename) = $poly->get_tag_values('locus_tag');
        $uniquename .= '.p' . sprintf( "%02d", $pos );
    }
    else {
        $uniquename = $accession;
    }

    my $poly_hash = {
        organism_id => $self->organism_row->organism_id,
        uniquename  => $uniquename,
        name        => $uniquename,
        type_id     => $self->find_cvterm_id( 'polypeptide', 'sequence' ),
        residues    => $peptide,
        md5checksum => md5_hex($peptide),
        seqlen      => length $peptide,
        is_analysis => 1,
        dbxref      => {
            accession => $accession,
            db_id     => $self->mod_dbrow->db_id,
        },
        feature_dbxrefs =>
            [ { dbxref_id => $self->get_dbxref_row('GenBank')->dbxref_id } ]
    };

    $self->add_featureprops( $poly, $poly_hash );
    $self->add_dbxrefs( $poly, $poly_hash );

    ## -- relationship with parent feature
    $poly_hash->{feature_relationship_subjects} = [
        {   object_id => $stack->transcript_row->feature_id,
            type_id => $self->find_cvterm_id( 'derives_from', 'relationship' )
        }
    ];

    my $poly_row
        = $self->schema->resultset('Sequence::Feature')->create($poly_hash);

    $self->logger->info( "loaded polypeptide ", $poly_row->uniquename );

}

sub add_featureprops {
    my ( $self, $feat, $data_hash ) = @_;
TAG:
    for my $t ( $feat->get_all_tags ) {
        next TAG if $self->is_tag_to_filter($t);
        my ($val) = $feat->get_tag_values($t);

        ## -- special case for protein_id tag
        ## -- it will be additionally stored as feature dbxref as GenePept id
        if ( $t eq 'protein_id' ) {
            push @{ $data_hash->{feature_dbxrefs} },
                {
                dbxref => {
                    accession => $val,
                    db_id     => $self->find_or_create_db_id($t)
                }
                };
        }
        push @{ $data_hash->{featureprops} },
            {
            value   => $val,
            type_id => $self->find_cvterm_id( $t, 'feature_property' )
            };
    }
}

sub add_dbxrefs {
    my ( $self, $feat, $data_hash ) = @_;
    return if !$feat->has_tag('db_xref');

    for my $value ( $feat->get_tag_values('db_xref') ) {
        my ( $db, $id ) = split /:/, $value;

        ## -- in chado the feature dbxrefs gets the 'DB' prefix
        $db = 'DB:' . $db;
        push @{ $data_hash->{feature_dbxrefs} }, {
            dbxref => {
                accession => $id,
                db_id     => $self->find_or_create_db_id($db)

            }
        };
    }
}

sub find_cvterm_id {
    my ( $self, $cvterm, $cv ) = @_;

    if ( $self->has_cvterm_row($cvterm) ) {
        return $self->get_cvterm_row($cvterm)->cvterm_id;
    }

    my $cvterm_rs = $self->schema->resultset('Cv::Cvterm')->search(
        {   'me.name' => $cvterm,
            'cv.name' => [ $cv, 'sequence' ]
        },
        { join => 'cv' }
    );

    if ( !$cvterm_rs->count ) {
        $self->logger->error(
            "$cvterm cvterm not found under namespace $cv and sequence
        ontology"
        );
        die;
    }

    my $row = $cvterm_rs->first;
    $self->add_cvterm_row( $cvterm, $row );
    return $row->cvterm_id;

}

sub find_or_create_db_id {
    my ( $self, $db ) = @_;
    ## -- check cache
    return $self->get_dbrow($db)->db_id if $self->has_dbrow($db);

    my $reg = $self->mod_registry;
    my $rs  = $self->schema->resultset('General::Db');

    ## -- now check if it has an alias
    my $orig;
    if ( $reg->has_alias($db) ) {
        $orig = $db;
        $db   = $reg->get_alias($db);
    }

    ## -- now lookup in the database
    my $dbrow = $rs->find( { name => $db } );
    if ( !$dbrow ) {    ## not there
        my $hash;
        if ( $reg->has_db($db) ) {    ## probe registry
            $hash = {
                name        => $db,
                urlprefix   => $reg->get_url_prefix($db),
                url         => $reg->get_url($db),
                description => $reg->get_description($db)
            };

        }
        else {
            $hash->{name} = $db;
        }
        $dbrow = $rs->create($hash);
    }
    $self->add_dbrow( $db, $dbrow );
    $self->add_dbrow( $orig, $dbrow ) if $orig;
    return $dbrow->db_id;
}

sub next_feature_id {
    my ($self) = @_;
    my $id = $self->schema->storage->dbh_do(
        sub {
            my ( $st, $dbh ) = @_;
            my $id = $dbh->selectcol_arrayref(
                "SELECT SQ_FEATURE_FEATURE_ID.NEXTVAL FROM DUAL")->[0];
            return $id;
        }
    );
    return sprintf( "%07d", $id );
}

sub chado_dbxref {
    my ($self) = @_;
    my $schema = $self->schema;
    my $dbrow  = $schema->resultset('General::Db')
        ->find_or_create( { name => 'GFF_source' } );
    my $dbxref_row = $schema->resultset('General::Dbxref')->find_or_create(
        {   accession => 'GenBank',
            db_id     => $dbrow->db_id
        }
    );
    $self->chado_dbrow($dbrow);
    $self->add_dbxref_row( 'GenBank', $dbxref_row );
}

sub calculate_polypeptide_seq {
    my ( $self, $trans ) = @_;
    my $model = Bio::SeqFeature::Gene::Transcript->new(
        -seq_id => 'model_transcript', 
        -strand => $trans->strand,
        -start  => $trans->start,
        -end    => $trans->end
    );
    $model->attach_seq( $trans->seq->seq );
    my @exons = $trans->location->each_Location;
    for my $i ( 0 .. $#exons ) {
        $model->add_exon(
            Bio::SeqFeature::Gene::Exon->new(
                -seq_id => 'exon' . $i,
                -strand => $exons[$i]->strand,
                -start  => $exons[$i]->start,
                -end    => $exons[$i]->end
            )
        );
    }
    return $model->cds->translate( -complete => 1 );
}

sub linkfeat2pub {
    my ( $self, $pubid ) = @_;
    my $schema = $self->schema;
    my $logger = $self->logger;

    my $row
        = $schema->resultset('Pub::Pub')->find( { uniquename => $pubid } );
    if ( !$row ) {
        $schema->resultset('Pub::Pub')->find( { pub_id => $pubid } );
        if ( !$row ) {
            $logger->warn(
                "cannot find $pubid in the database: no feature will be linked"
            );
            return;
        }
    }
    my $rs = $schema->resultset('Sequence::Feature')->search(
        {   'me.feature_id' =>
                { -in => [ $self->all_ids_from_scaffold_cache ] }
        }
    );
    my $rs2
        = $rs->search_related( 'featureloc_srcfeatures', {} )->search_related(
        'feature',
        { 'type.name' => { -in => [ $self->all_feat2link ] } },
        { 'join'      => 'type' }
        );

    $self->_link_feat2pub_rs( $rs,  $row );
    $self->_link_feat2pub_rs( $rs2, $row );
}

sub _link_feat2pub_rs {
    my ( $self, $rs, $row ) = @_;
    my $id    = $row->pub_id;
    my $pubid = $row->uniquename;

    my $feat2publinks;
    my $schema = $self->schema;
    my $logger = $self->logger;

    while ( my $row = $rs->next ) {
        push @$feat2publinks, [ $row->feature_id, $id ];
        if ( @$feat2publinks >= 5000 ) {
            unshift @$feat2publinks, [qw/feature_id pub_id/];
            $schema->resultset('Sequence::FeaturePub')
                ->populate($feat2publinks);
            $logger->info("linked 5000 feautres to $pubid");
            undef $feat2publinks;
        }
    }
    if ( defined $feat2publinks ) {
        unshift @$feat2publinks, [qw/feature_id pub_id/];
        $schema->resultset('Sequence::FeaturePub')->populate($feat2publinks);
        $logger->info(
            "linked rest of ",
            scalar @$feat2publinks,
            " features"
        );
    }
}

__PACKAGE__->meta->make_immutable;

1;
