package Modware::Loader::Ontology::Manager;

use namespace::autoclean;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use Carp;
use Encode;
use Modware::Types qw/Row/;
use utf8;

with 'Modware::Role::Chado::Helper::BCS::WithDataStash' =>
    { create_stash_for =>
        [qw/cvterm_dbxrefs cvtermsynonyms cvtermprop_cvterms/] };

has 'helper' => (
    is      => 'rw',
    isa     => 'Modware::Loader::Ontology::Helper',
    trigger => sub {
        my ( $self, $helper ) = @_;
        $self->meta->make_mutable;
        my $engine = 'Modware::Loader::Role::Ontology::With'
            . ucfirst lc( $helper->chado->storage->sqlt_type );
        ensure_all_roles( $self, $engine );
        $self->meta->make_immutable;
        $self->setup;
    }
);

has 'node' => (
    is        => 'rw',
    isa       => 'GOBO::Node|GOBO::LinkStatement',
    clearer   => 'clear_node',
    predicate => 'has_node'
);

has 'graph' => (
    is  => 'rw',
    isa => 'GOBO::Graph'
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
                $self->helper->chado->resultset('Cv::Cv')->search(
                {   name => {
                        -not_in =>
                            [ 'relationship', $self->cv_namespace->name ]
                    }
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

has 'skipped_message' => (
    is      => 'rw',
    isa     => 'Str',
    clearer => 'clear_message'
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

    my ( $dbxref_id, $db_id, $accession );
    if ( $self->helper->has_idspace( $node->id ) ) {
        my ( $db, $id ) = $self->helper->parse_id( $node->id );
        $db_id     = $self->helper->find_or_create_db_id($db);
        $dbxref_id = $self->helper->find_dbxref_id_by_cvterm(
            dbxref => $id,
            db     => $db,
            cvterm => $node->label,
            cv     => $node->namespace
            ? $node->namespace
            : $self->cv_namespace->name
        );
        $accession = $id;

    }
    else {
        my $namespace
            = $node->namespace
            ? $node->namespace
            : $self->cv_namespace->name;

        $db_id     = $self->helper->find_or_create_db_id($namespace);
        $dbxref_id = $self->helper->find_dbxref_id_by_cvterm(
            dbxref => $node->id,
            db     => $namespace,
            cvterm => $node->label,
            cv     => $namespace
        );
        $accession = $node->id;
    }

    if ($dbxref_id) {    #-- node is already present
        $self->skipped_message(
            "Node is already present with $dbxref_id acc:$accession db: $db_id"
        );
        return;
    }

    $self->add_to_mapper(
        'dbxref' => { accession => $accession, db_id => $db_id } );
    if ( $node->definition ) {
        $self->add_to_mapper( 'definition',
            encode( "UTF-8", $node->definition ) );
    }

    #logic if node has its own namespace defined
    if ( $node->namespace
        and ( $node->namespace ne $self->cv_namespace->name ) )
    {
        if ( $self->helper->exist_cvrow( $node->namespace ) ) {
            $self->add_to_mapper( 'cv_id',
                $self->helper->get_cvrow( $node->namespace )->cv_id );
        }
        else {
            my $row = $self->helper->chado->txn_do(
                sub {
                    $self->helper->chado->resultset('Cv::Cv')
                        ->create( { name => $node->namespace } );
                }
            );
            $self->helper->set_cvrow( $node->namespace, $row );
            $self->add_to_mapper( 'cv_id', $row->cv_id );
        }
    }
    else {
        $self->add_to_mapper( 'cv_id', $self->cv_namespace->cv_id );
    }
    $self->add_to_mapper( 'is_relationshiptype', 1 )
        if ref $node eq 'GOBO::RelationNode';

    if ( $node->obsolete ) {
        $self->add_to_mapper( 'is_obsolete', 1 );
    }
    else {
        $self->add_to_mapper( 'is_obsolete', 0 );
    }

    if ( $node->isa('GOBO::TermNode') ) {
        if ( $self->is_term_in_cache( $node->label ) ) {
            my $term = $self->get_term_from_cache( $node->label );
            if (    ( $term->[0] eq $self->get_map('cv_id') )
                and ( $term->[1] eq $self->get_map('is_obsolete') ) )
            {
                $self->skipped_message("Node is already processed");
                return;
            }
        }
    }

    $self->add_to_mapper( 'name', $node->label );
    $self->add_to_term_cache( $node->label,
        [ $self->get_map('cv_id'), $self->get_map('is_obsolete') ] )
        if $node->isa('GOBO::TermNode');

    return 1;

}

sub handle_alt_ids {
    my ($self) = @_;
    my $node = $self->node;
    return if !$node->alt_ids;
    for my $alt_id ( @{ $node->alt_ids } ) {
        if ( $self->helper->has_idspace($alt_id) ) {
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
                        db_id     => $self->db_namespace->db_id
                    }
                }
            );
        }
    }
}

sub handle_xrefs {
    my ($self) = @_;
    my $xref_hash = $self->node->xref_h;
    for my $key ( keys %$xref_hash ) {
        my $xref = $xref_hash->{$key};
        my ( $dbxref_id, $db_id, $accession );
        if (    $self->helper->has_idspace( $xref->id )
            and $xref->id !~ /^http/ )
        {
            my ( $db, $id ) = $self->helper->parse_id( $xref->id );
            $db_id = $self->helper->find_or_create_db_id($db);
            if ( !$db or !$id ) {

                #xref not getting parsed
                next;
            }
            $accession = $id;
            $dbxref_id = $self->helper->find_dbxref_id(
                db     => $db_id,
                dbxref => $id
            );

        }
        else {

            $db_id     = $self->db_namespace->db_id;
            $accession = $xref->id;
            $dbxref_id = $self->helper->find_dbxref_id(
                db     => $db_id,
                dbxref => $accession
            );
        }

        if ($dbxref_id) {
            $self->add_to_insert_cvterm_dbxrefs(
                { dbxref_id => $dbxref_id } );
        }
        elsif ( $self->xref_is_tracked($accession) ) {
            $self->add_to_xref_cache( $accession,
                [ $self->node->label, $db_id ] );
        }
        else {
            my $insert_hash
                = { dbxref => { accession => $accession, db_id => $db_id } };

            #if ( $xref->label ) {
            #$insert_hash->{dbxref}->{description} = $xref->label;
            #}
            $self->add_to_insert_cvterm_dbxrefs($insert_hash);
            $self->add_to_xref_tracker( $accession, 1 );
        }

    }
}

sub handle_synonyms {
    my ($self) = @_;
    $self->_handle_synonyms;
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

