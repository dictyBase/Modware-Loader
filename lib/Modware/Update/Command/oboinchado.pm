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
use MooseX::Params::Validate;
extends qw/Modware::Update::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Command::WithCounter' => { counter_for =>
        [qw/relations_loaded relations_skip terms_loaded terms_skip/] };

# Module implementation
#

has 'do_parse_id' => (
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
    my $schema = $self->chado;
    my $engine = Modware::Factory::Chado::BCS->new(
        engine => $schema->storage->sqlt_type );
    $engine->transform($schema);

    my $parser
        = GOBO::Parsers::OBOParserDispatchHash->new( file => $self->input );
    $self->parser($parser);

    # 1. Validation/Verification
    ## -- currently there is no validation steps
    ## -- will add here if something comes up

    # 3. Setup before loading
    ## -- the ontology and db namespace lookup
    my $global_cv = $schema->txn_do(
        sub {
            return $schema->resultset('Cv::Cv')
                ->find_or_create( { name => $self->namespace } );
        }
    );
    my $global_db = $schema->txn_do(
        sub {
            return $schema->resultset('General::Db')
                ->find_or_create( { name => '_global' } );
        }
    );

    my $helper = Modware::Loader::Ontology::Helper->new( runner => $self );
    my $manager = Modware::Loader::Ontology::Manager->new( runner => $self );
    $manager->cvrow($global_cv);
    $manager->dbrow($global_db);
    $manager->graph( $self->graph );

    my $loader = Modware::Loader::Ontology->new( manager => $manager );
    $loader->resultset('Cv::Cvterm');

    $self->manager($manager);
    $self->helper($helper);
    $self->loader($loader);

    my ( %total, %new_count, %exist_count );
    for my $type (qw/relations terms/) {
        my ( $new_nodes, $exist_nodes ) = $self->intersect_nodes($type);
        if ( defined $new_nodes ) {
            $self->load_new_nodes( $type, $new_nodes );
            $new_count{$type} = scalar @$new_nodes;
            $total{$type}     = $new_count{$type};
        }

        if ( defined $exist_nodes ) {
            $self->update_nodes( $type, $exist_nodes );
            $exist_count{$type} = scalar @$exist_nodes;
            $total{$type}
                = defined $total{$type}
                ? $total{$type} + $exist_count{$type}
                : $exist_count{$type};
        }
    }

    ## -- relationships
    my $edges = $self->graph->statements;
    $self->manager->clean_cache;
    $self->loader->resultset('Cv::CvtermRelationship');
    $self->load_relationships($edges);

    ## -- probably use a stat flag
    for my $type (qw/relations terms/) {
        $log->info( "Total $type:$total{$type} Loaded:",
            $self->relationships_loaded, " Skipped:",
            $self->relationships_skipped );
    }
}

sub load_relationships {
    my ( $self, $edges ) = @_;
}

sub intersect_terms {
    my ( $self, $type ) = @_;

    ## -- get all unique namespaces for terms
    my $namespaces = [
        uniq( $self->namespace, map { $_->namespace } $self->graph->$type ) ];

    my $schema = $self->chado;
    my $rs     = $schema->resultset('Cv::Cvterm')->search(
        {   'cv.name'     => { -in => $namespaces },
            'is_obsolete' => 0,
            'is_relationshiptype' => $type eq 'relations' ? 1 : 0,
        }
    );

    my %ids_from_db;
    if ( $self->do_parse_id ) {
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
        = [ grep { not defined $ids_from_db{ $_->id } } $self->graph->$type ];

    my $exist_terms
        = [ grep { defined $ids_from_db{ $_->id } } $self->graph->$type ];

    return ( $new_terms, $exist_terms );
}

sub load_new_nodes {
    my ($self) = shift;
    my ( $type, $terms ) = pos_validated_list(
        \@_,
        { isa => enum( [qw/terms relations/] ) },
        { isa => 'ArrayRef[GOBO::Node|GOBO::LinkStatement]' }
    );

NODE:
    for my $node (@$terms) {
        $self->manager->node($node);
        my $resp = $self->handle_core;
        if ( $resp->is_error ) {
            $self->current_logger->error( $resp->message );
            $type eq 'relations'
                ? $self->incr_relations_skip
                : $self->incr_terms_skip;
            next NODE;
        }

        for my $api ( map { 'handle_' . $_ }
            qw/synonyms alt_ids xrefs comment/ )
        {
            my $resp = $self->manager->$api;
            if ( $resp->is_error ) {
                $self->current_logger->error( $resp->message );
            }
        }

        if ( $type eq 'relations' ) {
            $self->manager->handle_rel_prop($_)
                for (qw/transitive reflexive cyclic anonymous/);
            $self->manager->handle_rel_prop( $_, 'value' )
                for (qw/domain range/);
        }
        $self->manager->keep_state_in_cache;
        $self->manager->clear_current_state;

        if ( $self->manager->entries_in_cache >= $self->commit_threshold ) {
            my $entries = $self->manager->entries_in_cache;

            $self->current_logger->info(
                "going to load $entries relationships ....");
            $self->loader->store_cache( $self->manager->cache );
            $self->manager->clean_cache;

            $self->current_logger->info(
                "loaded $entries relationship nodes  ....");

            $type eq 'relations'
                ? $self->set_rel_loaded_count(
                $self->relations_loaded + $entries )
                : $self->set_terms_loaded( $self->terms_loaded + $entries );
        }
    }
    if ( $self->manager->entries_in_cache ) {
        my $entries = $self->manager->entries_in_cache;

        $self->current_logger->info(
            "going to load $entries relationships ....");
        $self->loader->store_cache( $self->manager->cache );
        $self->manager->clean_cache;

        $self->current_logger->info(
            "loaded $entries relationship nodes  ....");

        $type eq 'relations'
            ? $self->set_relations_loaded(
            $self->relations_loaded + $entries )
            : $self->set_terms_loaded( $self->terms_loaded + $entries );
    }
}

sub update_nodes {
    my $self = shift;
    my ( $type, $terms ) = pos_validated_list(
        \@_,
        { isa => enum( [qw/terms relations/] ) },
        { isa => 'ArrayRef[GOBO::Node|GOBO::LinkStatement]' }
    );

}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Update ontology in chado database

