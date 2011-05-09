package Modware::Update::Command::oboinchado;

# Other modules:
use namespace::autoclean;
use Moose;
use Try::Tiny;
use Carp;
use Modware::Factory::Chado::BCS;
use Bio::Chado::Schema;
use GOBO::Parsers::OBOParserDispatchHash;
use Modware::Loader::OntoHelper;
use List::MoreUtils qw/uniq/;
extends qw/Modware::Update::Command/;
with 'Modware::Role::Command::WithLogger';

# Module implementation
#

has 'parse_id' => (
    default => 1,
    is      => 'rw',
    isa     => 'Bool',
    lazy    => 1,
    documentation =>
        q{Flag indicating that values stored or will be stored in dbxref
    table would be considered in DB:accession_number format. The DB value is expect in
    db.name and accession_number would be as dbxref.accession}
);
has '+data_dir' => ( traits   => [qw/NoGetopt/] );
has '+input'    => ( required => 1 );
has 'commit_threshold' => (
    lazy        => 1,
    default     => 1000,
    is          => 'rw',
    isa         => 'Int',
    traits      => [qw/Getopt/],
    cmd_aliases => 'ct',
    documentation =>
        'No of entries that will be cached before it is commited to the database'
);

has 'parser' => (
    is      => 'rw',
    isa     => 'GOBO::Parsers',
    traits  => [qw/NoGetopt/],
    trigger => sub {
        my ( $self, $parser ) = @_;
        $parser->parse;
    }
);

has 'graph' => (
    is      => 'ro',
    isa     => 'GOBO::Graph',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->parser->graph;
    }
);

has 'namespace' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my $self = shift;
        return $self->parser->default_namespace;
    }
);

has 'manager' => (
    is  => 'rw',
    isa => 'Modware::Loader::Ontology::Manager',
);

has 'helper' => (
    is  => 'rw',
    isa => 'Modware::Loader::Ontology::Helper',
);

has 'loader' => (
    is  => 'rw',
    isa => 'Modware::Loader::Ontology::Loader',
);

sub execute {
    my $self   = shift;
    my $log    = $self->logger;
    my $schema = $self->schema;
    my $engine = Modware::Factory::Chado::BCS->new(
        engine => $schema->storage->sqlt_type );
    $engine->transform($schema);

    my $parser
        = GOBO::Parsers::OBOParserDispatchHash->new( file => $self->input );
    $self->parser($parser);

    ## -- the ontology should exist in the database
    my $global_cv
        = $schema->resultset('Cv::Cv')->find( { name => $self->namespace } );
    if ( !$global_cv ) {
        $log->error( "Given ontology "
                . $self->namespace
                . " do not exist in database" );
        warn "could not ontology !!!! Check the log output\n";
        $log->logdie("!!! Could not load a new one !!!!");
    }
    my $global_db
        = $schema->resultset('General::Db')->find( { name => '_global' } );

    my $helper = Modware::Loader::Ontology::Helper->new( chado => $schema );
    my $manager
        = Modware::Loader::Ontology::Manager->new( helper => $helper );
    $manager->cvrow($global_cv);
    $manager->dbrow($global_db);
    $manager->graph( $self->graph );

    my $loader = Modware::Loader::Ontology->new( manager => $manager );
    $loader->resultset('Cv::Cvterm');

    $self->manager($manager);
    $self->helper($helper);
    $self->loader($loader);

    ## -- intersect relationship nodes
    my ( $new_rel, $exist_rel ) = $self->intersect_terms('relation');

}

sub intersect_terms {
    my ( $self, $relation ) = @_;

    ## -- get all uniquename namespaces for terms
    my $namespaces = [
        uniq (
            $self->namespace,
            map { $_->namespace } $relation
            ? @{ $self->graph->relations }
            : @{ $self->graph->terms }
        )
    ];

    my $schema = $self->schema;
    my $rs     = $schema->resultset('Cv::Cvterm')->search(
        {   'cv.name'     => { -in => $namespaces },
            'is_obsolete' => 0,
            'is_relationshiptype' => $relation ? 1 : 0,
        }
    );

    my %ids_from_db;
    if ( $self->parse_ids ) {
        %ids_from_db
            = map { $_->{db}->{name} . ':' . $_->{accession} => 1 }
            $rs->search_related(
            'dbxref',
            {},
            {   result_class => 'DBIx::Class::ResultClass::HashRefInflator',
                prefetch     => 'db'
            }
            );
    }
    else {
        %ids_from_db = map { $_->{accession} => 1 } $rs->search_related(
            'dbxref',
            {},
            { result_class => 'DBIx::Class::ResultClass::HashRefInflator', }
        );
    }

    my $new_terms
        = [ grep { not defined $ids_from_db{ $_->id } }
            $relation
        ? @{ $self->graph->relations }
        : @{ $self->graph->terms } ];

    my $exist_terms
        = [ grep { defined $ids_from_db{ $_->id } }
            $relation
        ? @{ $self->graph->relations }
        : @{ $self->graph->terms } ];

    return ( $new_terms, $exist_terms );
}

sub load_new_terms {
}

sub update_terms {
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Update ontology in chado database

