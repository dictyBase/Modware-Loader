package Modware::Loader::Ontology::Manager;

use namespace::autoclean;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use Carp;
use Encode;
use Modware::Types qw/Row/;
use utf8;
use Modware::Loader::Response;

with 'Modware::Role::Chado::Helper::BCS::WithDataStash' =>
    { create_stash_for =>
        [qw/cvterm_dbxrefs cvtermsynonyms cvtermprop_cvterms/] };

has 'runner' => (
    is      => 'rw',
    isa     => 'MooseX::App::Cmd::Command',
    trigger => sub {
        my ( $self, $runner ) = @_;
        my $helper = $runner->helper;
        $self->meta->make_mutable;
        my $engine = 'Modware::Loader::Role::Ontology::With'
            . ucfirst lc( $helper->chado->storage->sqlt_type );
        ensure_all_roles( $self, $engine );
        $self->meta->make_immutable;
        $self->setup;
    },
    handles => [qw/helper chado do_parse_id graph current_logger/]
);

has 'node' => (
    is        => 'rw',
    isa       => 'GOBO::Node|GOBO::LinkStatement',
    clearer   => 'clear_node',
    predicate => 'has_node'
);

has 'cvrow' => (
    is  => 'rw',
    isa => Row,
);

has 'dbrow' => (
    is  => 'rw',
    isa => Row
);

has 'other_cvs' => (
    is         => 'rw',
    isa        => 'ArrayRef',
    auto_deref => 1,
    default    => sub {
        my ($self) = @_;
        my $names = [
            map { $_->name }
                $self->runner->chado->resultset('Cv::Cv')->search(
                {   name =>
                        { -not_in => [ 'relationship', $self->cvrow->name ] }
                }
                )
        ];
        return $names;
    },
    lazy => 1
);

has 'xref_cache' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        add_to_xref_cache      => 'set',
        get_from_xref_cache    => 'get',
        clean_xref_cache       => 'clear',
        entries_in_xref_cache  => 'count',
        cached_xref_entries    => 'keys',
        exist_in_xref_cache    => 'defined',
        remove_from_xref_cache => 'delete'
    }
);

has 'xref_tracker_cache' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        add_to_xref_tracker     => 'set',
        clean_xref_tracker      => 'clear',
        entries_in_xref_tracker => 'count',
        tracked_xref_entries    => 'keys',
        xref_is_tracked         => 'defined',
        remove_xref_tracking    => 'delete'
    }
);

has 'cache' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    default => sub { [] },
    handles => {
        add_to_cache     => 'push',
        clean_cache      => 'clear',
        entries_in_cache => 'count',
        cache_entries    => 'elements'
    }
);

has 'term_cache' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        add_to_term_cache   => 'set',
        clean_term_cache    => 'clear',
        terms_in_cache      => 'count',
        terms_from_cache    => 'keys',
        is_term_in_cache    => 'defined',
        get_term_from_cache => 'get'
    }
);

before [ map { 'handle_' . $_ }
        qw/core alt_ids xrefs synonyms comment rel_prop/ ] => sub {
    my ($self) = @_;
    croak "node is not set\n" if !$self->has_node;
        };

sub handle_core {
    my ($self) = @_;
    my $node = $self->node;

    #if ( $node->replaced_by ) {
    #    $self->skipped_message(
    #        'Node is replaced by ' . $node->replaced_by );
    #    return;
    #}

    #if ( $node->consider ) {
    #    $self->skipped_message(
    #        'Node has been considered for replacement by '
    #            . $node->consider );
    #    return;
    #}

    my ( $db_id, $accession );
    if (    $self->do_parse_id
        and $self->helper->has_idspace( $node->id ) )
    {
        my ( $db, $accession ) = $self->helper->parse_id( $node->id );
        $db_id = $self->helper->find_or_create_db_id($db);
    }
    else {
        my $namespace
            = $node->namespace
            ? $node->namespace
            : $self->cvrow->name;

        $db_id     = $self->helper->find_or_create_db_id($namespace);
        $accession = $node->id;
    }

    $self->add_to_mapper(
        'dbxref' => { accession => $accession, db_id => $db_id } );

    #logic if node has its own namespace defined
    if ( $node->namespace
        and ( $node->namespace ne $self->cvrow->name ) )
    {
        if ( $self->helper->exist_cvrow( $node->namespace ) ) {
            $self->add_to_mapper( 'cv_id',
                $self->helper->get_cvrow( $node->namespace )->cv_id );
        }
        else {
            my $row = $self->chado->txn_do(
                sub {
                    $self->chado->resultset('Cv::Cv')
                        ->create( { name => $node->namespace } );
                }
            );
            $self->helper->set_cvrow( $node->namespace, $row );
            $self->add_to_mapper( 'cv_id', $row->cv_id );
        }
    }
    else {    ## -- use the global namespace
        $self->add_to_mapper( 'cv_id', $self->cvrow->cv_id );
    }

    $self->add_to_mapper( 'definition', encode( "UTF-8", $node->definition ) )
        if $node->defintion;
    $self->add_to_mapper( 'is_relationshiptype', 1 )
        if ref $node eq 'GOBO::RelationNode';
    $self->add_to_mapper( 'is_obsolete', 1 ) if $node->is_obsolete;

    if ( $node->isa('GOBO::TermNode') ) {
        if ( $self->is_term_in_cache( $node->label ) ) {
            my $term = $self->get_term_from_cache( $node->label );
            if (    ( $term->[0] eq $self->get_map('cv_id') )
                and ( $term->[1] eq $self->get_map('is_obsolete') ) )
            {
                return Modware::Loader::Response->new(
                    is_error => 1,
                    message  => 'Node ' . $node->id . ' is already processed'
                );
            }
        }
    }

    $self->add_to_mapper( 'name', $node->label );
    $self->add_to_term_cache( $node->label,
        [ $self->get_map('cv_id'), $self->get_map('is_obsolete') ] )
        if $node->isa('GOBO::TermNode');

    return Modware::Loader::Response->new(
        is_success => 1,
        message    => 'Node ' . $node->id . ' is successfully processed'
    );

}

sub handle_alt_ids {
    my ($self) = @_;
    my $node = $self->node;
    return if !$node->alt_ids;
    for my $alt_id ( @{ $node->alt_ids } ) {
        if ( $self->do_parse_id and $self->helper->has_idspace($alt_id) ) {
            my ( $db, $id ) = $self->helper->parse_id($alt_id);
            $self->add_to_insert_cvterm_dbxrefs(
                {   dbxref => {
                        accession => $id,
                        db_id     => $self->helper->find_or_create_db_id($db)
                    }
                }
            );

        }
        else {
            $self->add_to_insert_cvterm_dbxrefs(
                {   dbxref => {
                        accession => $alt_id,
                        db_id     => $self->dbrow->db_id
                    }
                }
            );
        }
    }
    return Modware::Loader::Response->new(
        is_success => 1,
        message    => 'All alt_ids are processed for ' . $node->id
    );

}

sub handle_xrefs {
    my ($self) = @_;
    my $xref_hash = $self->node->xref_h;

XREF:
    for my $key ( keys %$xref_hash ) {
        my $xref = $xref_hash->{$key};
        my ( $dbxref_id, $db_id, $accession );
        if (    $self->do_parse_id
            and $self->helper->has_idspace( $xref->id )
            and $xref->id !~ /^http/ )
        {
            my ( $db, $id ) = $self->helper->parse_id( $xref->id );
            $db_id = $self->helper->find_or_create_db_id($db);
            if ( !$db or !$id ) {

                #xref not getting parsed
                $self->current_logger->warn(
                    "cannot parse xref $xref for " . $self->node->id );
                next XREF;
            }
            $accession = $id;
            $dbxref_id = $self->helper->find_dbxref_id(
                db     => $db_id,
                dbxref => $id
            );

        }
        else {
            $db_id     = $self->dbrow->db_id;
            $accession = $xref->id;
            $dbxref_id = $self->helper->find_dbxref_id(
                db     => $db_id,
                dbxref => $accession
            );
        }
        ## the dbxref lookup is done as multiple nodes can share them

        if ($dbxref_id) {    ## -- shared dbxrefs present in database
            $self->add_to_insert_cvterm_dbxrefs(
                { dbxref_id => $dbxref_id } );
        }
        elsif ( $self->xref_is_tracked($accession) ) {
            ## -- shared dbxrefs in cache: not stored in the database yet
            $self->add_to_xref_cache( $accession,
                [ $self->node->label, $db_id ] );
        }
        else {               ## -- new dbxref not either in cache or database
            my $insert_hash
                = { dbxref => { accession => $accession, db_id => $db_id } };
            $self->add_to_insert_cvterm_dbxrefs($insert_hash);
            $self->add_to_xref_tracker( $accession, 1 );
        }
    }
    return Modware::Loader::Response->new(
        is_success => 1,
        message    => 'All dbxrefs are processed for ' . $self->node->id
    );
}

sub handle_comment {
    my ($self) = @_;
    my $node = $self->node;
    return if !$node->comment;
    $self->add_to_insert_cvtermprop_cvterms(
        {   value   => $node->comment,
            type_id => $self->helper->find_or_create_cvterm_id(
                db     => 'internal',
                dbxref => 'comment',
                cvterm => 'comment',
                cv     => 'cvterm_property_type'
            )
        }
    );
	return Modware::Loader::Response->new(
        is_success => 1,
        message    => 'comments are processed for ' . $node->id
    );
}

sub handle_rel_prop {
    my ( $self, $prop, $value ) = @_;
    my $node = $self->node;
    return if !$node->$prop;
    $self->add_to_insert_cvtermprop_cvterms(
        {   value => $value ? $node->$prop : 1,
            type_id => $self->helper->find_or_create_cvterm_id(
                db     => 'internal',
                dbxref => $prop,
                cvterm => $prop,
                cv     => 'cvterm_property_type'
            )
        }
    );

	return Modware::Loader::Response->new(
        is_success => 1,
        message    => "relation property $prop processed for " . $node->id
    );
}

sub keep_state_in_cache {
    my ($self) = @_;
    $self->add_to_cache( $self->insert_hashref );
}

sub clear_current_state {
    my ($self) = @_;
    $self->clear_stashes;
    $self->clear_node;
}

sub handle_relation {
    my ($self)     = @_;
    my $node       = $self->node;
    my $graph      = $self->graph;
    my $type       = $node->relation;
    my $subject    = $node->node;
    my $object     = $node->target;
    my $subj_inst  = $graph->get_node($subject);
    my $obj_inst   = $graph->get_node($object);
    my $default_cv = $self->cv_namespace->name;

    my $type_id = $self->helper->find_relation_term_id(
        cv     => [ $default_cv, 'relationship', $self->other_cvs ],
        cvterm => $type
    );

    if ( !$type_id ) {
        $self->skipped_message("$type relation node not in storage");
        return;
    }

    my $subject_id = $self->helper->find_cvterm_id_by_term_id(
        term_id => $subject,
        cv      => $subj_inst->namespace
    );
    if ( !$subject_id ) {
        $self->skipped_message("subject $subject not in storage");
        return;
    }

    my $object_id = $self->helper->find_cvterm_id_by_term_id(
        term_id => $object,
        cv      => $obj_inst->namespace
    );

    if ( !$object_id ) {
        $self->skipped_message("object $object not in storage");
        return;
    }

    $self->add_to_mapper( 'type_id',    $type_id );
    $self->add_to_mapper( 'subject_id', $subject_id );
    $self->add_to_mapper( 'object_id',  $object_id );
    return 1;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

