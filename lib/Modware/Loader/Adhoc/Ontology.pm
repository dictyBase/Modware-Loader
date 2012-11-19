package Modware::Loader::Adhoc::Ontology;

use namespace::autoclean;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use Carp;
use Encode;
use utf8;
use Modware::Loader::Response;

with 'Modware::Loader::Adhoc::Role::Ontology::Helper';
with 'Modware::Role::Chado::Helper::BCS::WithDataStash' =>
    { create_stash_for =>
        [qw/cvterm_dbxrefs cvtermsynonyms cvtermprop_cvterms/] };

has 'chado' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    trigger => sub { $self->load_engine(@_) }
);
has 'cv_namespace' =>
    ( is => 'rw', isa => 'Bio::Chado::Scheme::Result::Cv::Cv' );
has 'db_namespace' =>
    ( is => 'rw', isa => 'Bio::Chado::Scheme::Result::General::Db' );

# revisit
sub load_engine {
    my ( $self ) = @_;
    $self->meta->make_mutable;
    my $engine = 'Modware::Loader::Role::Ontology::With'
        . ucfirst lc( $chado->storage->sqlt_type );
    ensure_all_roles( $self, $engine );
    $self->meta->make_immutable;
    $self->setup;
}

has 'term' => (
    is        => 'rw',
    isa       => 'Bio::Ontology::TermI',
    clearer   => 'clear_term',
    predicate => 'has_term'
);

#revisit
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

#revisit
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

#revisit
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

sub update_or_create_term {
	my ($self, $term, $relation) = @_;
	if (my $term_from_db = $self->find_cvterm_by_id($term->identifier)) {
		$self->_update_term($term_from_db, $term);
	}
	else {
		$self->_insert_term($term, $relation);
	}
}

sub _update_term {
	my ($self, $term_from_db, $term) = @_;
	if ($term_from_db->is_obsolete != $term->is_obsolete) {
		$term_from_db->update({is_obsolete => $term->is_obsolete});
	}
}

sub _insert_term {
    my ($self, $term, $relation) = @_;
    my ( $db_id, $accession );
    if (
        $self->has_idspace( $term->identifier ) )
    {
        my ( $db, $accession ) = $self->parse_id( $term->identifier );
        $db_id = $self->find_or_create_db_id($db);
    }
    else {
        $db_id     = $self->find_or_create_db_id( $self->cvrow->name );
        $accession = $term->identifier;
    }

    $self->add_to_mapper(
        'dbxref' => { accession => $accession, db_id => $db_id } );

    ## -- use the global namespace
    $self->add_to_mapper( 'cv_id', $self->cvrow->cv_id );
    $self->add_to_mapper( 'definition', encode( "UTF-8", $term->definition ) )
        if $term->defintion;
    $self->add_to_mapper( 'is_relationshiptype', 1 ) if $relation;
    $self->add_to_mapper( 'is_obsolete', 1 ) if $term->is_obsolete;
    $self->add_to_mapper( 'name', $term->name );

    my $row = $self->chado->resultset('Cv::Cvterm')->create($self->insert_hashref);
    $self->clear_stashes;
    return $row;
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
    my ($self)    = @_;
    my $node      = $self->node;
    my $graph     = $self->graph;
    my $type      = $node->relation;
    my $subject   = $node->node;
    my $object    = $node->target;
    my $subj_inst = $graph->get_node($subject);
    my $obj_inst  = $graph->get_node($object);

    my $type_id = $self->find_relation_term_id(
        cv     => [ $self->cvrow->name, 'relationship' ],
        cvterm => $type
    );

    if ( !$type_id ) {
        return Modware::Loader::Response->new(
            message  => "$type relation node not in storage",
            is_error => 1
        );
    }

    my $subject_id = $self->find_cvterm_id_by_term_id(
        term_id => $subject,
        cv      => $subj_inst->namespace
    );

    if ( !$subject_id ) {
        return Modware::Loader::Response->new(
            message  => "subject $subject not in storage",
            is_error => 1
        );
    }

    my $object_id = $self->find_cvterm_id_by_term_id(
        term_id => $object,
        cv      => $obj_inst->namespace
    );

    if ( !$object_id ) {
        return Modware::Loader::Response->new(
            message  => "object $object not in storage",
            is_error => 1
        );
    }

    $self->add_to_mapper( 'type_id',    $type_id );
    $self->add_to_mapper( 'subject_id', $subject_id );
    $self->add_to_mapper( 'object_id',  $object_id );
    return 1;
}

sub store_cache {
    my ( $self, $cache ) = @_;
    my $chado = $self->manager->chado;

    my $index;
    try {
        $chado->txn_do(
            sub {
                #$chado->resultset( $self->resultset )->populate($cache);
                for my $i ( 0 .. scalar @$cache - 1 ) {
                    $index = $i;
                    $chado->resultset( $self->resultset )
                        ->create( $cache->[$i] );
                }
            }
        );
    }
    catch {
        warn "error in creating: $_";
        croak Dumper $cache->[$index];
    };
}

#Not getting to be used for the time being
sub handle_alt_ids {
    my ($self) = @_;
    my $node = $self->node;
    return if !$node->alt_ids;
    for my $alt_id ( @{ $node->alt_ids } ) {
        if ( $self->do_parse_id and $self->has_idspace($alt_id) ) {
            my ( $db, $id ) = $self->parse_id($alt_id);
            $self->add_to_insert_cvterm_dbxrefs(
                {   dbxref => {
                        accession => $id,
                        db_id     => $self->find_or_create_db_id($db)
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
            and $self->has_idspace( $xref->id )
            and $xref->id !~ /^http/ )
        {
            my ( $db, $id ) = $self->parse_id( $xref->id );
            $db_id = $self->find_or_create_db_id($db);
            if ( !$db or !$id ) {

                #xref not getting parsed
                $self->current_logger->warn(
                    "cannot parse xref $xref for " . $self->node->id );
                next XREF;
            }
            $accession = $id;
            $dbxref_id = $self->find_dbxref_id(
                db     => $db_id,
                dbxref => $id
            );

        }
        else {
            $db_id     = $self->dbrow->db_id;
            $accession = $xref->id;
            $dbxref_id = $self->find_dbxref_id(
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
            type_id => $self->find_or_create_cvterm_id(
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
            type_id => $self->find_or_create_cvterm_id(
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

sub process_xref_cache {
    my ($self) = @_;
    my $cache;
    my $chado = $self->manager->chado;
ACCESSION:
    for my $acc ( $self->manager->cached_xref_entries ) {
        my $data = $self->manager->get_from_xref_cache($acc);
        my $rs   = $chado->resultset('General::Dbxref')
            ->search( { accession => $acc, db_id => $data->[1] } );
        next ACCESSION if !$rs->count;

        my $cvterm = $chado->resultset('Cv::Cvterm')->find(
            {   name        => $data->[0],
                is_obsolete => 0,
                cv_id       => $self->manager->cv_namespace->cv_id
            }
        );
        next ACCESSION if !$cvterm;
        push @$cache,
            {
            cvterm_id => $cvterm->cvterm_id,
            dbxref_id => $rs->first->dbxref_id
            };

        $self->manager->remove_from_xref_cache($acc);
    }

    $chado->txn_do(
        sub {
            $chado->resultset('Cv::CvtermDbxref')->populate($cache);
        }
    ) if defined $cache;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

<MODULE NAME> - [One line description of module's purpose here]


=head1 VERSION

This document describes <MODULE NAME> version 0.0.1


=head1 SYNOPSIS

use <MODULE NAME>;

=for author to fill in:
Brief code example(s) here showing commonest usage(s).
This section will be as far as many users bother reading
so make it as educational and exeplary as possible.


=head1 DESCRIPTION

=for author to fill in:
Write a full description of the module and its features here.
Use subsections (=head2, =head3) as appropriate.


=head1 INTERFACE 

=for author to fill in:
Write a separate section listing the public components of the modules
interface. These normally consist of either subroutines that may be
exported, or methods that may be called on objects belonging to the
classes provided by the module.

=head2 <METHOD NAME>

=over

=item B<Use:> <Usage>

[Detail text here]

=item B<Functions:> [What id does]

[Details if neccessary]

=item B<Return:> [Return type of value]

[Details]

=item B<Args:> [Arguments passed]

[Details]

=back

=head2 <METHOD NAME>

=over

=item B<Use:> <Usage>

[Detail text here]

=item B<Functions:> [What id does]

[Details if neccessary]

=item B<Return:> [Return type of value]

[Details]

=item B<Args:> [Arguments passed]

[Details]

=back


=head1 DIAGNOSTICS

=for author to fill in:
List every single error and warning message that the module can
generate (even the ones that will "never happen"), with a full
explanation of each problem, one or more likely causes, and any
suggested remedies.

=over

=item C<< Error message here, perhaps with %s placeholders >>

[Description of error here]

=item C<< Another error message here >>

[Description of error here]

[Et cetera, et cetera]

=back


=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in:
A full explanation of any configuration system(s) used by the
module, including the names and locations of any configuration
files, and the meaning of any environment variables or properties
that can be set. These descriptions must also include details of any
configuration language used.

<MODULE NAME> requires no configuration files or environment variables.


=head1 DEPENDENCIES

=for author to fill in:
A list of all the other modules that this module relies upon,
  including any restrictions on versions, and an indication whether
  the module is part of the standard Perl distribution, part of the
  module's distribution, or must be installed separately. ]

  None.


  =head1 INCOMPATIBILITIES

  =for author to fill in:
  A list of any modules that this module cannot be used in conjunction
  with. This may be due to name conflicts in the interface, or
  competition for system or program resources, or due to internal
  limitations of Perl (for example, many modules that use source code
		  filters are mutually incompatible).

  None reported.


  =head1 BUGS AND LIMITATIONS

  =for author to fill in:
  A list of known problems with the module, together with some
  indication Whether they are likely to be fixed in an upcoming
  release. Also a list of restrictions on the features the module
  does provide: data types that cannot be handled, performance issues
  and the circumstances in which they may arise, practical
  limitations on the size of data sets, special cases that are not
  (yet) handled, etc.

  No bugs have been reported.Please report any bugs or feature requests to
  dictybase@northwestern.edu



  =head1 TODO

  =over

  =item *

  [Write stuff here]

  =item *

  [Write stuff here]

  =back


  =head1 AUTHOR

  I<Siddhartha Basu>  B<siddhartha-basu@northwestern.edu>


  =head1 LICENCE AND COPYRIGHT

  Copyright (c) B<2003>, Siddhartha Basu C<<siddhartha-basu@northwestern.edu>>. All rights reserved.

  This module is free software; you can redistribute it and/or
  modify it under the same terms as Perl itself. See L<perlartistic>.


  =head1 DISCLAIMER OF WARRANTY

  BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
  FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
  OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
  PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
  EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
  ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
  YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
  NECESSARY SERVICING, REPAIR, OR CORRECTION.

  IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
  WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
  REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
  LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL,
  OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE
  THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING
		  RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A
		  FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER SOFTWARE), EVEN IF
  SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF
  SUCH DAMAGES.



