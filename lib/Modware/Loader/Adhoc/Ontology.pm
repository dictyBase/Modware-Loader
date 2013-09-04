package Modware::Loader::Adhoc::Ontology;

use namespace::autoclean;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use Carp;
use Encode;
use utf8;

with 'Modware::Role::Chado::Helper::BCS::WithDataStash';

has 'logger' => ( is => 'rw', isa => 'Log::Log4perl::Logger' );
has 'app_instance' =>
    ( is => 'rw', isa => 'Modware::Load::Command::adhocobo2chado' );

has 'chado' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    trigger => sub {
        my ( $self, $schema ) = @_;
        $self->load_engine($schema);
    }
);
has 'cv_namespace' =>
    ( is => 'rw', isa => 'Bio::Chado::Schema::Result::Cv::Cv' );
has 'db_namespace' =>
    ( is => 'rw', isa => 'Bio::Chado::Schema::Result::General::Db' );

# revisit
sub load_engine {
    my ( $self, $schema ) = @_;
    $self->meta->make_mutable;
    my $engine = 'Modware::Loader::Adhoc::Role::Ontology::Chado::With'
        . ucfirst lc( $self->chado->storage->sqlt_type );
    ensure_all_roles( $self, $engine );
    $self->meta->make_immutable;
    $self->transform_schema($schema);
}

sub update_or_create_term {
    my ( $self, $term ) = @_;
    my $term_from_db
        = $self->find_cvterm_by_id( $term->id, $self->cv_namespace->name );
    if ($term_from_db) {
        $self->_update_term( $term_from_db, $term );
        $self->logger->debug( 'update term ', $term->id );
        return 'update';
    }
    else {
        $self->_insert_term($term);
        $self->logger->debug( 'insert term ', $term->id );
        return 'insert';
    }
}

sub _update_term {
    my ( $self, $term_from_db, $term ) = @_;
    if ( $term_from_db->is_obsolete != $term->is_obsolete ) {
        $term_from_db->update(
            {   is_obsolete => $term->is_obsolete,
                definition  => $term->def->text
            }
        );
    }
}

sub _insert_term {
    my ( $self, $term ) = @_;
    my ( $db_id, $accession );
    if ( $self->has_idspace( $term->id ) ) {
        my @parsed = $self->parse_id( $term->id );
        $db_id     = $self->find_or_create_db_id( $parsed[0] );
        $accession = $parsed[1];
    }
    else {
        $db_id     = $self->find_or_create_db_id( $self->cv_namespace->name );
        $accession = $term->id;
    }

    my $insert_hash;
    $insert_hash->{dbxref}     = { accession => $accession, db_id => $db_id };
    $insert_hash->{cv_id}      = $self->cv_namespace->cv_id;
    $insert_hash->{definition} = encode( "UTF-8", $term->def->text )
        if $term->def;
    $insert_hash->{is_relationshiptype} = 1
        if $term->isa('OBO::Core::RelationshipType');
    $insert_hash->{is_obsolete} = 1 if $term->is_obsolete;
    $insert_hash->{name} = $term->name ? $term->name : $term->id;

    return $self->chado->resultset('Cv::Cvterm')->create($insert_hash);
}

sub load_namespaces {
    my ( $self, $ontology ) = @_;
    my $global_cv = $self->chado->resultset('Cv::Cv')
        ->find_or_create( { name => $ontology->default_namespace } );
    my $global_db = $self->chado->resultset('General::Db')
        ->find_or_create( { name => '_global' } );
    $self->cv_namespace($global_cv);
    $self->db_namespace($global_db);
    $self->find_or_create_cvterm_namespace;
}

sub find_or_create_namespaces {
    my ($self) = @_;
    $self->find_or_create_dbrow('internal');
    $self->find_or_create_cvrow($_) for qw/cvterm_property_type synonym_type/;
    $self->find_or_create_cvterm_namespace($_)
        for
        qw/comment alt_id xref cyclic reflexive transitive anonymous domain range/;
    $self->find_or_create_cvterm_namespace( $_, 'synonym_type' )
        for qw/EXACT BROAD NARROW RELATED/;

}


sub create_relationship {
    my ( $self, $relation ) = @_;
    my $cv     = $self->cv_namespace->name;
    my $logger = $self->logger;

    my $relationship_from_db
        = $self->find_relation_term( $relation->type, $cv );
    if ( !$relationship_from_db ) {
        $logger->error( $relation->type, " relation do no exist in storage" );
        return;
    }
    my $subject = $self->find_cvterm_by_id( $relation->tail->id, $cv );
    if ( !$subject ) {
        $logger->error( $relation->tail->id,
            " subject term do not exist in storage" );
        return;
    }

    my $object = $self->find_cvterm_by_id( $relation->head->id, $cv );
    if ( !$object ) {
        $logger->error( $relation->head->id,
            " object term do not exist in storage" );
        return;
    }

    my $relation_from_db
        = $self->find_relation( $subject, $object, $relationship_from_db );
    if ($relation_from_db) {
        $logger->debug("!!!! relation exist in database");
        return;
    }

    my $row = $self->chado->resultset('Cv::CvtermRelationship')->create(
        {   object_id  => $object->cvterm_id,
            subject_id => $subject->cvterm_id,
            type_id    => $relationship_from_db->cvterm_id
        }
    );
    $logger->debug( "created relationship ",
        $relation->type, " between ",
        $relation->tail->id, " and ", $relation->head->id );
    return $row;
}

sub delete_comment {
    my ( $self, $term_from_db ) = @_;
    $term_from_db->delete_related(
        'cvtermprops',
        { 'type.name' => 'comment', 'cv.name' => 'cvterm_property_type' },
        { join        => [          { 'type'  => 'cv' } ] }
    );
}

sub create_comment {
    my ( $self, $term, $term_from_db ) = @_;
    $term_from_db->create_related(
        'cvtermprops',
        {   value   => $term->comment,
            type_id => $self->find_or_create_cvterm_namespace( 'comment',
                'cvterm_property_type' )->cvterm_id
        }
    );
}

sub delete_alt_ids {
    my ( $self, $term_from_db ) = @_;
    my @dbxrefs
        = $term_from_db->search_related( 'cvterm_dbxrefs', {} )
        ->search_related(
        'dbxrefs',
        {   db_id => {
                -in => [
                    $term_from_db->dbxref->db_id,
                    $self->find_or_create_db_id( $self->cv_namespace->name )
                ]
            }
        }
        );
    $_->delete for @dbxrefs;
}

sub create_alt_ids {
    my ( $self, $term, $term_from_db ) = @_;
    my $set = $term->alt_id;
    for my $alt_id ( $set->get_set ) {
        if ( $self->has_idspace($alt_id) ) {
            my ( $db, $id ) = $self->parse_id($alt_id);
            $term_from_db->create_related(
                'cvterm_dbxrefs',
                {   dbxref => {
                        accession => $id,
                        db_id     => $self->find_or_create_db_id($db)
                    }
                }
            );
        }
        else {
            $term_from_db->create_related(
                'cvterm_dbxrefs',
                {   dbxref => {
                        accession => $alt_id,
                        db_id     => $self->find_or_create_db_id(
                            $self->cv_namespace->name
                        )
                    }
                }
            );
        }
    }
}

sub delete_synonyms {
    my ( $self, $term_from_db ) = @_;
    $term_from_db->delete_related(
        'cvtermsynonyms',
        {   'cv.name'   => 'synonym_type',
            'type.name' => { -in => [qw/BROAD EXACT NARROW RELATED/] }
        },
        { join => [ { 'type' => 'cv' } ] }
    );
}

sub create_synonyms {
    my ( $self, $term, $term_from_db ) = @_;
    for my $syn ( $term->synonym_set ) {
        $term_from_db->create_related(
            'cvtermsynonyms',
            {   value   => $syn->def->text,
                type_id => $self->find_or_create_cvterm_namespace(
                    $syn->scope, 'synonym_type'
                )
            }
        );
    }
}

sub delete_xrefs {
    my ( $self, $term_from_db ) = @_;
    my @dbxrefs
        = $term_from_db->search_related( 'cvterm_dbxrefs', {} )
        ->search_related(
        'dbxrefs',
        {   db_id => {
                -not_in => [
                    $term_from_db->dbxref->db_id,
                    $self->find_or_create_db_id( $self->cv_namespace->name )
                ]
            }
        }
        );
    $_->delete for @dbxrefs;
}

sub create_xrefs {
    my ( $self, $term, $term_from_db ) = @_;
    my $set = $term->xref_set;
    for my $xref ( $set->get_set ) {
        if ( $self->has_idspace($xref->name) ) {
            my ( $db, $id ) = $self->parse_id($xref->name);
            $term_from_db->create_related(
                'cvterm_dbxrefs',
                {   dbxref => {
                        accession => $id,
                        db_id     => $self->find_or_create_db_id($db)
                    }
                }
            );
        }
        else {
            $term_from_db->create_related(
                'cvterm_dbxrefs',
                {   dbxref => {
                        accession => $xref->name,
                        db_id     => $self->find_or_create_db_id(
                            $self->cv_namespace->name
                        )
                    }
                }
            );
        }
    }
}

with 'Modware::Loader::Adhoc::Role::Ontology::Helper';

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



