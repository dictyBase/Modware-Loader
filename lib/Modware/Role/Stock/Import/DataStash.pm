
package Modware::Role::Stock::Import::DataStash;

use strict;

use Moose::Role;
use namespace::autoclean;
use feature qw/say/;
use LWP::Simple;
use JSON;

requires 'schema';
requires 'logger';

has '_pmc_url' => (
    is  => 'rw',
    isa => 'Str',
    default =>
        'http://www.ebi.ac.uk/europepmc/webservices/rest/search?query=ext_id:'
);

has 'db' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'internal',
    traits  => [qw/NoGetopt/]
);

has 'cv' => (
    is     => 'rw',
    isa    => 'Str',
    traits => [qw/NoGetopt/]
);

has '_organism_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_organism_row => 'set',
        get_organism_row => 'get',
        has_organism_row => 'defined'
    }
);

sub find_organism {
    my ( $self, $name ) = @_;
    my @organism = split( /\s+/, $name );
    if ( $self->has_organism_row($name) ) {
        return $self->get_organism_row($name)->organism_id;
    }
    my $species
        = ( scalar @organism == 3 )
        ? join( ' ', @organism[ 1, 2 ] )
        : $organism[1];
    my $row = $self->schema->resultset('Organism::Organism')
        ->search( { species => $species, genus => $organism[0] } );
    if ( $row->count > 0 ) {
        $self->set_organism_row( $name, $row->first );
        return $self->get_organism_row($name)->organism_id;
    }
}

sub find_or_create_organism {
    my ( $self, $name ) = @_;
    if ( my $id = $self->find_organism($name) ) {
        return $id;
    }
    my @organism = split( /\s+/, $name );
    my $species
        = @organism == 3 ? join( ' ', @organism[ 1, 2 ] ) : $organism[1];
    my $new_organism_row
        = $self->schema->resultset('Organism::Organism')->create(
        {   genus        => $organism[0],
            species      => $species,
            abbreviation => substr( $organism[0], 0, 1 ) . "." . $species
        }
        );
    $self->set_organism_row( $name, $new_organism_row );
    return $self->get_organism_row($name)->organism_id;
}

has '_cvterm_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_cvterm_row => 'set',
        get_cvterm_row => 'get',
        has_cvterm_row => 'defined'
    }
);

sub find_all_cvterms {
    my ( $self, $cv ) = @_;
    return [ map { $_->cvterm_id }
            $self->schema->resultset('Cv::Cvterm')
            ->search( { 'cv.name' => $cv }, { join => 'cv' } ) ];
}

sub find_cvterm {
    my ( $self, $name, $cv_name ) = @_;

    if ( $self->has_cvterm_row($name) ) {
        return $self->get_cvterm_row($name)->cvterm_id;
    }
    my $row = $self->schema->resultset('Cv::Cvterm')->search(
        { 'me.name' => $name, 'cv.name' => $cv_name },
        { join      => 'cv',  select    => [qw/cvterm_id name/] }
    );
    if ( $row->count > 0 ) {
        $self->set_cvterm_row( $name, $row->first );
        return $self->get_cvterm_row($name)->cvterm_id;
    }
}

sub find_or_create_cvterm {
    my ( $self, $cvterm, $cv ) = @_;
    my $cvterm_id = $self->find_cvterm( $cvterm, $cv );
    if ( !$cvterm_id ) {
        my $row = $self->schema->resultset('Cv::Cvterm')->create(
            {   name      => $cvterm,
                dbxref_id => $self->find_or_create_dbxref($cvterm),
                cv_id     => $self->find_or_create_cv($cv)
            }
        );
        $self->set_cvterm_row( $cvterm, $row );
        $cvterm_id = $row->cvterm_id;
    }
    return $cvterm_id;
}

sub find_or_create_cv {
    my ( $self, $cv ) = @_;
    $self->cv($cv) if $cv;
    my $row = $self->schema->resultset('Cv::Cv')
        ->find_or_create( { name => $self->cv } );
    my $cv_id;
    if ($row) {
        $cv_id = $row->cv_id;
    }
    return $cv_id;
}

sub find_or_create_dbxref {
    my ( $self, $accession ) = @_;
    my $params = {
        accession => $accession,
        db_id     => $self->find_or_create_db()
    };
    my $rs = $self->schema->resultset('General::Dbxref')->search($params);
    if ( $rs->count ) {
        return $rs->first->dbxref_id;
    }
    my $row = $self->schema->resultset('General::Dbxref')->create($params);
    return $row->dbxref_id;
}

sub find_or_create_db {
    my ($self) = @_;
    my $db_rs = $self->schema->resultset('General::Db')
        ->find_or_create( { name => $self->db } );
    return $db_rs->db_id;
}

has '_stock_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_stock_row => 'set',
        get_stock_row => 'get',
        has_stock_row => 'defined',
        get_dbs_ids   => 'keys'
    }
);

sub find_stock_object {
    my ( $self, $id ) = @_;
    if ( $self->has_stock_row($id) ) {
        return $self->get_stock_row($id);
    }
    my $row = $self->schema->resultset('Stock::Stock')
        ->search( { uniquename => $id }, {} );
    if ( $row->count > 0 ) {
        $self->set_stock_row( $id, $row->first );
        return $self->get_stock_row($id);
    }
    return;
}

sub find_stock {
    my ( $self, $id ) = @_;
    if ( $self->has_stock_row($id) ) {
        return $self->get_stock_row($id)->stock_id;
    }
    my $row = $self->schema->resultset('Stock::Stock')
        ->search( { uniquename => $id }, {} );
    if ( $row->count > 0 ) {
        $self->set_stock_row( $id, $row->first );
        return $self->get_stock_row($id)->stock_id;
    }
    return;
}

sub find_stock_by_name {
    my ( $self, $name ) = @_;
    my $stock_id;
    my $rs = $self->schema->resultset('Stock::Stock')
        ->search( { name => $name }, {} );
    if ( $rs->count > 0 ) {
        $stock_id = $rs->first->stock_id;
    }
    return $stock_id;
}

sub find_stock_name {
    my ( $self, $id ) = @_;
    if ( $self->has_stock_row($id) ) {
        return $self->get_stock_row($id)->name;
    }
    my $row = $self->schema->resultset('Stock::Stock')
        ->search( { uniquename => $id }, {} );
    if ( $row->count > 0 ) {
        $self->set_stock_row( $id, $row->first );
        return $self->get_stock_row($id)->name;
    }
    return;
}

has '_pub_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_pub_row => 'set',
        get_pub_row => 'get',
        has_pub_row => 'defined'
    }
);

sub find_pub {
    my ( $self, $pmid ) = @_;
    if ( $self->has_pub_row($pmid) ) {
        return $self->get_pub_row($pmid)->pub_id;
    }
    my $row
        = $self->schema->resultset('Pub::Pub')
        ->search( { uniquename => $pmid },
        { select => [qw/pub_id uniquename/] } );
    if ( $row->count > 0 ) {
        $self->set_pub_row( $pmid, $row->first );
        return $self->get_pub_row($pmid)->pub_id;
    }
}

sub find_or_create_pub {
    my ( $self, $pmid ) = @_;
    if ( my $pub_id = $self->find_pub($pmid) ) {
        return $pub_id;
    }
    my $pub_row = $self->create_pub_entry($pmid);
    if ($pub_row) {
        $self->set_pub_row( $pmid, $pub_row );
        return $pub_row->pub_id;
    }
}

sub find_pub_by_title {
    my ( $self, $title ) = @_;
    my $row = $self->schema->resultset('Pub::Pub')
        ->search( { title => $title }, { rows => 1 } )->single;
    if ($row) {
        $self->set_pub_row( $row->uniquename, $row );
        return $self->get_pub_row( $row->uniquename )->pub_id;
    }
}

sub create_pub_entry {
    my ( $self, $pubmed_id ) = @_;
    my $url = $self->_pmc_url . $pubmed_id . '&resulttype=core&format=json';
    $self->logger->debug("fetching $pubmed_id from $url");
    my $content = get($url);
    if ($content) {
        my $str      = decode_json($content);
        my $result   = $str->{resultList}->{result}->[0];
        my $pub_type = $self->find_cvterm( "journal_article", "pub_type" );
        my $schema   = $self->schema;
        my $pub_row  = $schema->resultset('Pub::Pub')->create(
            {   pubplace   => 'PubMed',
                uniquename => $pubmed_id,
                series_name =>
                    $result->{journalInfo}->{journal}->{medlineAbbreviation},
                title   => $result->{title},
                volume  => $result->{volume},
                pyear   => $result->{pubYear},
                pages   => $result->{pageInfo},
                type_id => $pub_type
            }
        );
        my $pub_id  = $pub_row->pub_id;
        my $authors = $result->{authorList}->{author};
        for my $i ( 0 .. $#$authors ) {
            $schema->resultset('Pub::Pubauthor')->create(
                {   surname    => $authors->[$i]->{lastName},
                    givennames => $authors->[$i]->{firstName},
                    pub_id     => $pub_id,
                    rank       => $i + 1
                }
            );
        }
        $pub_row->create_related(
            'pubprops',
            {   type_id => $self->find_cvterm( 'doi', 'pub_type' ),
                value   => $result->{doi}
            }
        ) if defined $result->{journalInfo}->{journal}->{doi};
        $pub_row->create_related(
            'pubprops',
            {   type_id => $self->find_cvterm( 'issn', 'pub_type' ),
                value => $result->{journalInfo}->{journal}->{issn}
            }
        ) if defined $result->{journalInfo}->{journal}->{issn};
        $pub_row->create_related(
            'pubprops',
            {   type_id => $self->find_cvterm( 'abstract', 'pub_type' ),
                value   => $result->{abstractText}
            }
        ) if defined $result->{abstractText};
        return $pub_row;
    }
}

has '_environment' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_env_row => 'set',
        get_env_row => 'get',
        has_env_row => 'defined'
    }
);

sub find_or_create_environment {
    my ( $self, $env_term ) = @_;
    $env_term = $self->utils->trim($env_term);
    if ( $self->has_env_row($env_term) ) {
        return $self->get_env_row($env_term)->environment_id;
    }
    my $cvterm_env;
    $cvterm_env = $self->find_cvterm( $env_term, 'Dicty Environment' );
    if ( !$cvterm_env ) {
        $cvterm_env = $self->find_or_create_cvterm( 'unspecified environment',
            'Dicty Environment' );
        $env_term = 'unspecified environment' if !$env_term;
    }
    my $env_rs = $self->schema->resultset('Genetic::Environment')
        ->find( { description => $env_term } );
    if ($env_rs) {
        $self->set_env_row( $env_term, $env_rs );
        return $self->get_env_row($env_term)->environment_id;
    }
    else {
        # my $uniquename = $self->generate_uniquename('DSC_ENV');
        my $uniquename = $self->utils->nextval( 'environment', 'DSC_ENV' );
        $env_rs
            = $self->schema->resultset('Genetic::Environment')
            ->create(
            { uniquename => $uniquename, description => $env_term } );
        $env_rs->create_related( 'environment_cvterms',
            { cvterm_id => $cvterm_env } );
        $self->set_env_row( $env_term, $env_rs );
        return $self->get_env_row($env_term)->environment_id;
    }
}

has '_strain_genotype' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_strain_genotype => 'set',
        get_strain_genotype => 'get',
        has_strain_genotype => 'defined'
    }
);

sub find_genotype {
    my ( $self, $dbs_id ) = @_;
    if ( $self->has_strain_genotype($dbs_id) ) {
        return $self->get_strain_genotype($dbs_id)->genotype_id;
    }

    my $stock_rs = $self->schema->resultset('Stock::StockGenotype')
        ->search( { 'stock.uniquename' => $dbs_id }, { join => 'stock' } );
    if ( $stock_rs->count > 0 ) {
        $self->set_strain_genotype( $dbs_id, $stock_rs->first );
        return $self->get_strain_genotype($dbs_id)->genotype_id;
    }
}

sub find_or_create_genotype {
    my ( $self, $dbs_id ) = @_;
    if ( $self->has_strain_genotype($dbs_id) ) {
        return $self->get_strain_genotype($dbs_id)->genotype_id;
    }

    my $stock_rs = $self->schema->resultset('Stock::StockGenotype')
        ->search( { 'stock.uniquename' => $dbs_id }, { join => 'stock' } );
    if ( $stock_rs->count > 0 ) {
        $self->set_strain_genotype( $dbs_id, $stock_rs->first );
        return $self->get_strain_genotype($dbs_id)->genotype_id;
    }
    else {
        my $stock_rs = $self->find_stock($dbs_id);
        if ( !$stock_rs ) {
            return;
        }

        # my $genotype_uniquename = $self->generate_uniquename('DSC_G');
        my $genotype_uniquename
            = $self->utils->nextval( 'genotype', 'DSC_G' );
        my $genotype_rs
            = $self->schema->resultset('Genetic::Genotype')->find_or_create(
            {   name       => $stock_rs->name,
                uniquename => $genotype_uniquename,
                type_id =>
                    $self->find_cvterm( 'genotype', 'dicty_stockcenter' ),
                stock_genotypes => [ { stock_id => $stock_rs->stock_id } ]
            }
            );
        $self->set_strain_genotype( $dbs_id, $genotype_rs );
        return $self->get_strain_genotype($dbs_id)->genotype_id;
    }
}

has '_phenotype' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_phenotype => 'set',
        get_phenotype => 'get',
        has_phenotype => 'defined'
    }
);

sub find_or_create_phenotype {
    my ( $self, $phenotype_term, $assay, $note ) = @_;
    if ( $self->has_phenotype($phenotype_term) ) {
        return $self->get_phenotype($phenotype_term)->phenotype_id;
    }
    my $cvterm_phenotype
        = $self->find_cvterm( $phenotype_term, "Dicty Phenotypes" );
    if ( !$cvterm_phenotype ) {
        $self->logger->warn(
            "Couldn't find \"$phenotype_term\" in Dicty phenotype ontology");
        return;
    }
    my $cvterm_assay = $self->find_cvterm( $assay, "Dictyostelium Assay" )
        if $assay;
    if ( !$cvterm_assay and $assay ) {
        my $msg = "Couldn't find \"$assay\" in Dicty assay ontology";
        $self->logger->warn($msg);
    }

    my $phenotype_hash;
    $phenotype_hash->{uniquename}
        = $self->utils->nextval( 'phenotype', 'DSC_PHEN' );
    $phenotype_hash->{observable_id} = $cvterm_phenotype;
    $phenotype_hash->{assay_id} = $cvterm_assay if $cvterm_assay;
    if ($note) {
        $note =~ s/(\[.*\])//;
        my $note_type_id = $self->find_or_create_cvterm( 'curator note',
            'dicty_stockcenter' );
        $phenotype_hash->{phenotypeprops}
            = [ { type_id => $note_type_id, value => $note } ]

    }

    my $phenotype_rs = $self->schema->resultset('Phenotype::Phenotype')
        ->find_or_create($phenotype_hash);

    if ($phenotype_rs) {
        $self->set_phenotype( $phenotype_term, $phenotype_rs );
        return $self->get_phenotype($phenotype_term)->phenotype_id;
    }
}

sub find_or_create_stockcollection {
    my ( $self, $name, $type_id ) = @_;
    my $id = $self->find_stockcollection($name);
    return $id if $id;
    return $self->create_stockcollection( $name, $type_id );
}

sub find_stockcollection {
    my ( $self, $name ) = @_;
    my $rs = $self->schema->resultset('Stock::Stockcollection')
        ->search( { name => $name } );
    if ( $rs->count > 0 ) {
        return $rs->first->stockcollection_id;
    }
}

sub create_stockcollection {
    my ( $self, $name, $type_id ) = @_;
    my $stockcollection_rs
        = $self->schema->resultset('Stock::Stockcollection')->create(
        {   type_id    => $type_id,
            name       => $name,
            uniquename => $self->utils->nextval( 'stockcollection', 'DSC' )
        }
        );
    return $stockcollection_rs->stockcollection_id;
}

sub has_strain_plasmid_map {
    my ( $self, $query ) = @_;
    my $count
        = $self->schema->resultset('Stock::StockRelationship')->count($query);
    return $count if $count;
}

sub has_phenstatement {
    my ( $self, $query ) = @_;
    my $count
        = $self->schema->resultset('Genetic::Phenstatement')->count($query);
    return $count if $count;
}

sub has_stock_pub {
    my ( $self, $query ) = @_;
    my $count
        = $self->schema->resultset('Stock::StockPub')->count($query);
    return $count if $count;
}


1;

__END__
