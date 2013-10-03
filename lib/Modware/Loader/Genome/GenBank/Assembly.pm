package Modware::Loader::Genome::GenBank::Assembly;
use namespace::autoclean;
use Moose;
use Bio::SeqIO;
use Digest::MD5 qw/md5_hex/;

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
        my ($self) = @_;
        my $hash   = {};
        my $rs     = $self->schema->resultset('Sequence::Feature')->search(
            {   'type.name'   => $self->reference_type,
                'organism_id' => $self->organism_row->organism_id
            },
            { join => [qw/type/] }
        );
        while ( my $row = $rs->next ) {
            $hash->{ $row->name } = $row->feature_id;
        }
        return $hash;
    },
    lazy    => 1,
    handles => {
        add_to_scaffold_cache   => 'set',
        get_from_scaffold_cache => 'get',
        all_from_scaffold_cache => 'keys',
        has_scaffold_cache      => 'defined'
    }
);

has 'mod_registry' => (
    is      => 'rw',
    isa     => 'Object',
    lazy    => 1,
    default => sub {
        return Modware::MOD::Registry->new;
    }
);

has 'contig_rgx' => (
    is      => 'rw',
    isa     => 'RegexpRef',
    lazy    => 1,
    default => sub {
        return qr/^(\w+)\.(\d{1,2}):(\d+)\.\.(\d+)$/;
    }
);

has 'gap_rgx' => (
    is      => 'rw',
    isa     => 'RegexpRef',
    lazy    => 1,
    default => sub {
        return qr/^gap\((unk)?(\d+)\)$/;
    }
);

has '_contig_stack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    lazy    => 1,
    default => sub { [] },
    handles => {
        'add_contig_to_cache'      => 'push',
        'all_contigs_from_cache'   => 'elements',
        'clear_contigs_from_cache' => 'clear'
    }
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

    ## setting species,  genus,  common name and abbreviation
    my $species
        = $strain
        ? $seq->species->species . ' ' . $strain
        : $seq->species->species;
    my $genus        = $seq->species->genus;
    my $common_name  = $seq->species->species;
    my $abbreviation = substr( $genus, 0, 1 ) . '.' . $species;

    my $org_row = $schema->resultset('Organism::Organism')
        ->find( { genus => $genus, species => $species } );

    if ($org_row) {
        $self->organism_row($org_row);
        $logger->info(
            "organism $genus $species $common_name is already present in database"
        );
        return;
    }

    $logger->info(
        "organism $genus $species $common_name not found in database, will try to create"
    );

    my $row = $schema->resultset('Organism::Organism')->create(
        {   genus        => $genus,
            species      => $species,
            abbreviation => $abbreviation,
            common_name  => $common_name,
        }
    );
    $self->organism_row($row);
}

sub add_featureprops {
    my ( $self, $feat, $data_hash ) = @_;
    for my $t ( $feat->get_all_tags ) {
        next if $self->is_tag_to_filter($t);
        my ($val) = $feat->get_tag_values($t);
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
        push @{ $data_hash->{feature_dbxrefs} }, {
            dbxref => {
                accession => $id,
                db_id     => $self->find_or_create_db_id($db)

            }
        };
    }
}

sub load_assembly {
    my ($self) = @_;

    my $seqio  = $self->seqio;
    my $schema = $self->schema;

ASSEMBLY:
    while ( my $seq = $seqio->next_seq ) {
        if ( !$self->has_organism_row ) {
            $self->find_or_create_organism($seq);
        }
        my $running_start = 0;
        my $running_end   = 0;
        my $length        = 0;
        my $start_flag    = 1;
        my $anno_str      = join '',
            map { $_->value } $seq->annotation->get_Annotations('contig');

        ## -- Important: For storing in chado all the coordinate are converted to interbase
        ## -- coordinates instead of base coordindates to accomodate zero length features,
        ## -- for example restriction enzyme sites. For a better explanation look here ....
        ## -- http://gmod.org/wiki/Introduction_to_Chado#Interbase_Coordinates

        ## -- generally in base coordinates length is ($end - $start) + 1
        ## -- in interbase coordinates length is $end - $start
        if ( $anno_str =~ /join\((.+)\)/ ) {
            my $location_str = $1;

            if ( $location_str !~ /\,/ ) {    ## -- single contig without gap
                if ( $location_str =~ $self->contig_rgx ) {
                    $running_start = $3 - 1;
                    $running_end   = $4;
                    $length        = ( $4 - $3 ) + 1;

                    my $accession
                        = $self->id_prefix . $self->next_feature_id();
                    my $sequence = $self->get_seq_from_db( $seq->display_id,
                        $running_start + 1, $running_end );
                    my $contig_hash = {
                        organism_id => $self->organism_row->organism_id,
                        uniquename  => $1,
                        name        => $1,
                        type_id =>
                            $self->find_cvterm_id( 'contig', 'sequence' ),
                        seqlen      => $length,
                        residues    => $sequence,
                        md5checksum => md5_hex($sequence),
                        dbxref      => {
                            accession => $accession,
                            db_id     => $self->mod_dbrow->db_id,
                            version   => $2
                        },
                        feature_dbxrefs => [
                            {   dbxref_id => $self->get_dbxref_row('GenBank')
                                    ->dbxref_id
                            }
                        ],
                        featureloc_features => [
                            {   srcfeature_id =>
                                    $self->get_from_scaffold_cache(
                                    $seq->display_id
                                    ),
                                fmin => $running_start,
                                fmax => $running_end
                            }
                        ]
                    };
                    my $row = $schema->resultset('Sequence::Feature')
                        ->create($contig_hash);
                    $self->add_contig_to_cache( $row->feature_id );

                    $self->logger->info( "loaded contig ",
                        $contig_hash->{uniquename} );
                }
                else {
                    $self->logger->warn(
                        "no matching contig or accession found");
                }
                next ASSEMBLY;
            }

            for my $loc ( split( /\,/, $location_str ) ) {
                if ( $loc =~ $self->contig_rgx ) {
                    $length = ( $4 - $3 ) + 1;
                    if ($start_flag) {    ## for the first contig
                        $running_start = $3 - 1;
                        $running_end   = $4;
                        $start_flag    = 0;
                    }
                    else {
                        $running_start = $running_end;
                        $running_end   = $running_start + $length;

                    }
                    my $accession
                        = $self->id_prefix . $self->next_feature_id();
                    my $sequence = $self->get_seq_from_db( $seq->display_id,
                        $running_start + 1, $running_end );
                    my $contig_hash = {
                        organism_id => $self->organism_row->organism_id,
                        uniquename  => $1,
                        name        => $1,
                        type_id =>
                            $self->find_cvterm_id( 'contig', 'sequence' ),
                        seqlen      => $length,
                        residues    => $sequence,
                        md5checksum => md5_hex($sequence),
                        dbxref      => {
                            accession => $accession,
                            db_id     => $self->mod_dbrow->db_id,
                            version   => $2
                        },
                        feature_dbxrefs => [
                            {   dbxref_id => $self->get_dbxref_row('GenBank')
                                    ->dbxref_id
                            }
                        ],
                        featureloc_features => [
                            {   srcfeature_id =>
                                    $self->get_from_scaffold_cache(
                                    $seq->display_id
                                    ),
                                fmin => $running_start,
                                fmax => $running_end
                            }
                        ]
                    };
                    my $row = $schema->resultset('Sequence::Feature')
                        ->create($contig_hash);
                    $self->add_contig_to_cache( $row->feature_id );

                    $self->logger->info( "loaded contig ",
                        $contig_hash->{uniquename} );

                }
                ## -- we safely assume that contig assembly cannot start with a gap
                ## -- so the coordinate scale is already being set
                elsif ( $loc =~ $self->gap_rgx ) {
                    $length = $2;    ## length is given explicitly
                    $running_start = $running_end;
                    $running_end   = $running_start + $length;

                    my $accession
                        = $self->id_prefix . $self->next_feature_id();
                    my $gap_hash = {
                        organism_id => $self->organism_row->organism_id,
                        uniquename  => $accession,
                        name        => $accession,
                        type_id => $self->find_cvterm_id( 'gap', 'sequence' ),
                        seqlen  => $length,
                        dbxref  => {
                            accession => $accession,
                            db_id     => $self->mod_dbrow->db_id,
                        },
                        feature_dbxrefs => [
                            {   dbxref_id => $self->get_dbxref_row('GenBank')
                                    ->dbxref_id
                            }
                        ],
                        featureloc_features => [
                            {   srcfeature_id =>
                                    $self->get_from_scaffold_cache(
                                    $seq->display_id
                                    ),
                                fmin => $running_start,
                                fmax => $running_end
                            }
                        ]
                    };

                    $schema->resultset('Sequence::Feature')
                        ->create($gap_hash);
                    $self->logger->info( "loaded gap ",
                        $gap_hash->{uniquename} );
                }
                else {
                    $self->logger->warn(
                        "no matching contig or accession found");
                }
            }
        }
    }
}

sub get_seq_from_db {
    my ( $self, $id, $start, $end ) = @_;
    my $rs = $self->schema->resultset('Sequence::Feature')->search(
        { 'uniquename' => $id },
        {   select => [ \"SUBSTR(residues, $start, $end)" ],
            as     => 'fseq'
        }
    );
    return $rs->first->get_column('fseq');
}

sub find_cvterm_id {
    my ( $self, $cvterm, $cv ) = @_;

    if ( $self->has_cvterm_row($cvterm) ) {
        return $self->get_cvterm_row($cvterm)->cvterm_id;
    }

    my $cvterm_rs = $self->schema->resultset('Cv::Cvterm')->search(
        {   'me.name' => $cvterm,
            'cv.name' => $cv
        },
        { join => 'cv' }
    );

    if ( !$cvterm_rs->count ) {
        $self->logger->error("$cvterm cvterm not found under namespace $cv");
        die;
    }

    my $row = $cvterm_rs->first;
    $self->add_cvterm_row( $cvterm, $row );
    return $row->cvterm_id;

}

sub find_or_create_db_id {
    my ( $self, $db ) = @_;
    return $self->get_dbrow($db)->db_id if $self->has_dbrow($db);
    my $dbrow = $self->schema->resultset('General::Db')
        ->find_or_create( { name => $db } );
    $self->add_dbrow( $db, $dbrow );
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
    my $id = $row->pub_id;
    my $feat2publinks;
    for my $featid ( $self->all_contigs_from_cache ) {
        push @$feat2publinks, [ $featid, $id ];
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
