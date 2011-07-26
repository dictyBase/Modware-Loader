package Modware::Update::Command::oboinchado;

# Other modules:
use namespace::autoclean;
use Moose;
use Try::Tiny;
use Carp;
use Modware::Factory::Chado::BCS;
use Bio::Chado::Schema;
use GOBO::Parsers::OBOParserDispatchHash;
use Digest::MD5 qw/md5/;
use Modware::Loader::OntoHelper;
use MooseX::Params::Validate;
extends qw/Modware::Update::Command/;
with 'Modware::Loader::Role::Onotoloy::WithHelper';
with 'Modware::Loader::Role::Temp::Obo';
with 'Modware::Role::Command::WithReportLogger';
with 'Modware::Role::Command::WithValidationLogger';

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

sub execute {
    my $self = shift;

    my $log     = $self->logger;
    my $vlogger = $self->validation_logger;

    my $schema = $self->chado;
    my $engine = Modware::Factory::Chado::BCS->new(
        engine => $schema->storage->sqlt_type );
    $engine->transform($schema);

    $vlogger->log('start parsing log file');

    my $parser
        = GOBO::Parsers::OBOParserDispatchHash->new( file => $self->input );
    $self->parser($parser);
    $parser->parse;
    $self->namespace( $parser->default_namespace );
    $vlogger->log('finished parsing log file');

    # 1. Validation/Verification
    if ( !$$parser->format_version >= 1.2 ) {
        $vlogger->log("obo format should be 1.2 or above");
        $vlogger->fatal( $parser->format_version, " not supported" );
    }

    $vlogger->info('generating graph for obo file');
    $self->graph( $parser->graph );
    $vlogger->info('finish generating graph for obo file');

    $self->_set_various_namespace;
    $self->_process_relations_to_memory;
    $self->_prcoess_nodes_to_memory;

    $self->load_all_in_tmp;

    #$self->load_tmp2chado;

    $schema->disconnect;

}

sub _process_relations_to_memory {
    my ($self) = @_;
    my $graph = $self->graph;
RELATION:
    for my $edge ( @{ $graph->statements } ) {
        my $subject  = $graph->get_node( $edge->node )->label;
        my $object   = $graph->get_node( $edge->target )->label;
        my $relation = $edge->relation;

        ## -- memory consumption
        my $md5 = md5( $subject . $object . $relation );
        next RELATION if $self->has_relation($md5);
        $self->add_relation( $md5, [ $subject, $object, $relation ] );
    }
}

sub _set_various_namespace {
    my ($self) = @_;
    my $schema = $self->chado;

    ## -- basic cv and db namespaces
    $self->cvrow(
        $schema->txn_do(
            sub {
                $schema->resultset('Cv::Cv')
                    ->find_or_create( { name => $self->namespace } );
            }
        )
    );
    $self->add_dbrow(
        'internal',
        $schema->txn_do(
            sub {
                $schema->resultset('General::Db')
                    ->find_or_create( { name => 'internal' } );
            }
        )
    );

    $self->add_cvrow(
        'cvterm_property_type',
        $schema->txn_do(
            sub {
                return $schema->resultset('Cv::Cv')
                    ->find_or_create( { name => 'cvterm_property_type' } );
            }
        )
    );

## -- setup for synonyms
    $self->add_cvrow(
        'synonym_type',
        $schema->txn_do(
            sub {
                return $schema->resultset('Cv::Cv')
                    ->find_or_create( { name => 'synonym_type' } );
            }
        )
    );

    for my $sc ( $self->synonym_scopes ) {
        $self->add_cvterm_row(
            $sc,
            $schema->txn_do(
                sub {
                    return $schema->resultset('Cv::Cvterm')->find_or_create(
                        {   name  => $sc,
                            cv_id => $self->get_cvrow('synonym_type')->cv_id,
                            dbxref_id => $schema->resultset('General::Dbxref')
                                ->find_or_create(
                                {   accession => $sc,
                                    db_id =>
                                        $self->get_dbrow('internal')->db_id
                                }
                                )->dbxref_id
                        }
                    );
                }
            )
        );
    }

    ## -- setup for comment
    $self->add_cvterm_row(
        'comment',
        $schema->txn_do(
            sub {
                $schema->resultset('Cv::Cvterm')->find_or_create(
                    {   cv_id =>
                            $self->get_cvrow('cvterm_property_type')->cv_id,
                        name      => 'comment',
                        dbxref_id => $schema->resultset('General::Dbxref')
                            ->find_or_create(
                            {   accession => 'comment',
                                db_id => $self->get_dbrow('internal')->db_id
                            }
                            )->dbxref_id
                    }
                );
            }
        )
    );

## -- setup for alt_id
    $self->set_cvterm_row(
        'alt_id',
        $schema->txn_do(
            sub {
                return $schema->resultset('Cv::Cvterm')->find_or_create(
                    {   cv_id =>
                            $self->get_cvrow('cvterm_property_type')->cv_id,
                        name      => 'alt_id',
                        dbxref_id => $schema->resultset('General::Dbxref')
                            ->find_or_create(
                            {   accession => 'alt_id',
                                db_id => $self->get_dbrow('internal')->db_id
                            }
                            )->dbxref_id
                    }
                );
            }
        )
    );

## -- setup for xrefs
    $self->get_cvterm_row(
        'xref',
        $schema->txn_do(
            sub {
                return $schema->resultset('Cv::Cvterm')->find_or_create(
                    {   cv_id =>
                            $self->get_cvrow('cvterm_property_type')->cv_id,
                        name      => 'xref',
                        dbxref_id => $schema->resultset('General::Dbxref')
                            ->find_or_create(
                            {   accession => 'xref',
                                db_id => $self->get_dbrow('internal')->db_id
                            }
                            )->dbxref_id
                    }
                );
            }
        )
    );

## -- relation terms properties
    for my $prop ( $self->relation_props ) {
        $self->set_cvterm_row(
            $prop,
            $schema->txn_do(
                sub {
                    return $schema->resultset('Cv::Cvterm')->find_or_create(
                        {   name  => $prop,
                            cv_id => $self->get_cvrow('cvterm_property_type')
                                ->cv_id,
                            dbxref_id => $schema->resultset('General::Dbxref')
                                ->find_or_create(
                                {   accession => $prop,
                                    db_id =>
                                        $self->get_dbrow('internal')->db_id
                                }
                                )->dbxref_id
                        }
                    );
                }
            );
        }
    }
}

sub _process_nodes_to_memory {
    my ( $self, %params ) = validated_hash(
        \@_,
        graph  => { isa => 'GOBO::Graph',        optional => 1 },
        schema => { isa => 'Bio::Chado::Schema', optional => 1 },
    );

    my $graph  = $params{graph}  || $self->graph;
    my $schema = $params{schema} || $self->schema;
    my $vlogger = $self->validation_logger;

NODE:
    for my $type ( $self->term_types ) {
        for my $node ( @{ $graph->$type } ) {
            my $status = $node->obsolete ? 1 : 0;
            my $label = $node->label;
            $label = $node->id if $node->id eq 'is_a';

            if ( $self->is_term_in_cache($label) ) {
                my $estatus = $self->get_term_from_cache($label)->[0];
                if ( $estatus == $status ) {
                    $vlogger->log( "DUPLICATE TERM:$label ", $node->id );
                    next NODE;
                }
            }
            $self->add_to_term_cache( $t->label, [ $status, $id ] );

            if ( $type eq 'relations' ) {
                for my $prop ( $self->relation_attributes ) {
                    $self->add_rel_attr(
                        [   $label, 1, $self->get_cvterm_row($prop)->cvterm_id
                        ]
                    ) if $node->$prop;
                }
                for my $prop ( $self->relation_properties ) {
                    $self->add_rel_attr(
                        [   $label, $t->$prop,
                            $self->get_cvterm_row($prop)->cvterm_id
                        ]
                    ) if $node->$prop;
                }
            }

            my $scope
                = $node->namespace ? $node->namespace : $default_namespace;
            my ( $db, $id );
            if ( $node->id =~ /:/ ) {
                ( $db, $id ) = split /:/, $node->id;
            }
            else {
                $db = $scope;
                $id = $node->id;
            }

            $self->add_dbrow(
                $db,
                $schema->txn_do(
                    sub {
                        = $schema->resultset('General::Db')
                            ->find_or_create( { name => $db } );
                    }
                )
            ) if !$self->has_dbrow($db);

            $self->add_cvrow(
                $scope,
                $schema->txn_do(
                    sub {
                        $schema->resultset('Cv::Cv')
                            ->find_or_create( { name => $scope } );
                    }
                )
            ) if !$self->has_cvrow($scope);

            $self->add_node(
                [   $label,
                    $self->get_dbrow($db)->db_id,
                    $self->get_cvrow($scope)->cv_id,
                    $id,
                    $node->definition
                    ? encode( "UTF-8", $node->definition )
                    : undef,
                    $status,
                    $type eq 'relations' ? 1 : 0,
                    $node->comment ? $node->comment : undef
                ]
            );

            ## -- synonyms
            $self->_process_synonyms_to_memory( $node, $label, $status );
            ## -- alt ids
            $self->_process_alt_ids_to_memory( $node, $label );
            ## -- xref data
            $self->process_xrefs_to_memory( $node, $label, $status );
        }
    }
}

sub _process_synonyms_to_memory {
    my ( $self, $node, $label, $status ) = @_;
    if ( defined $node->synonyms ) {
        my %uniq_sym = map { $_->scope => $_->label } @{ $node->synonyms };
        $self->add_synonym(
            [   $self->get_cvterm_row($_)->cvterm_id,
                $label, $uniq_sym{$_}, $status
            ]
        ) for keys %uniq_sym;
    }
}

sub _process_alt_ids_to_memory {
    my ( $self, $node, $label ) = @_;
    if ( defined $node->alt_ids ) {
        for my $alt_id ( @{ $node->alt_ids } ) {
            if ( $alt_id =~ /:/ ) {
                my ( $db, $id ) = split /:/, $alt_id;
                $self->add_dbrow(
                    $db,
                    $schema->txn_do(
                        sub {
                            = $schema->resultset('General::Db')
                                ->find_or_create( { name => $db } );
                        }
                    )
                ) if !$self->has_dbrow($db);
                $self->add_alt_row(
                    [ $alt_id, $label, $self->get_dbrow($db)->db_id ] );
            }
            else {
                $self->vlogger->log("skipping $alt_id alternate ids");
            }
        }
    }
}

sub _process_xrefs_to_memory {
    my ( $self, $node, $label, $status ) = @_;

    if ( defined $node->xref_h ) {
    VAL:
        for my $val ( values %{ $node->xref_h } ) {
            my ( $db, $id );
            if ( $val =~ /^http:http/ ) {
                $db = 'http';
                my ( $first, @rest ) = split /:/, $val;
                $id = join( ':', @rest );
            }
            elsif ( $val =~ /^http/ ) {
                $db = 'URL';
                $id = $val;
            }
            else {
                my @rest;
                ( $db, @rest ) = split /:/, $val;
                $id = join( ':', @rest );
            }

            $self->add_dbrow(
                $db,
                $schema->txn_do(
                    sub {
                        = $schema->resultset('General::Db')
                            ->find_or_create( { name => $db } );
                    }
                )
            ) if !$self->has_dbrow($db);

            $self->add_xref_row(
                [ $id, $label, $self->get_dbrow($db)->db_id, $status ] );
        }
    }
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Update ontology in chado database

