package Modware::EventHandler::FeatureReader::Chado;

# Other modules:
use namespace::autoclean;
use Moose;

# Module implementation
#
has 'reference_type' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'supercontig',
    lazy    => 1
);

has 'reference_id' => ( is => 'rw', isa => 'Str' );

sub read_seq_id_by_name {
    my ( $self, $event, $dbrow ) = @_;
    if ( my $name = $dbrow->name ) {
        $event->response_id($name);
        return;
    }
}

sub read_reference_by_id {
    my ( $self, $event, $dbrow ) = @_;
    my $reference_rs = $dbrow->search_related(
        'features',
        {   -or => [
                'me.name'          => $self->reference_id,
                'me.uniquename'    => $self->reference_id,
                'dbxref.accession' => $self->reference_id
            ],
            'type.name' => $self->reference_type
        },
        {   join => [qw/type dbxref/],
            '+select' =>
                [ { LENGTH => 'me.residues', -as => 'sequence_length' } ],
            cache => 1
        }
    );
    if ( !$reference_rs->count ) {
        $event->logger->logcroak(
            "no reference feature(s) found for organism ",
            $dbrow->common_name );
    }
    $event->response($reference_rs);
}

sub read_reference {
    my ( $self, $event, $dbrow ) = @_;
    my $reference_rs = $dbrow->search_related(
        'features',
        { 'type.name' => $self->reference_type },
        {   join     => 'type',
            '+select' =>
                [ { LENGTH => 'me.residues', -as => 'sequence_length' } ],
            cache => 1
        }
    );
    if ( !$reference_rs->count ) {
        $event->logger->logcroak(
            "no reference feature(s) found for organism ",
            $dbrow->common_name );
    }
    $event->response($reference_rs);
}

sub read_reference_without_mito {
    my ( $self, $event, $dbrow ) = @_;
    my $type = $self->reference_type;

    my $mito_rs = $dbrow->search_related(
        'features',
        {   'type.name'   => $type,
            'type_2.name' => 'mitochondrial_DNA',
            'cv.name'     => 'sequence'
        },
        { join => [ 'type', { 'featureprops' => { 'type' => 'cv' } } ] }
    );

    my $nuclear_rs;
    if ( $mito_rs->count ) {    ## -- mitochondrial genome is present
        $nuclear_rs = $dbrow->search_related(
            'features',
            {   'feature_id' => {
                    -not_in => $mito_rs->get_column('feature_id')->as_query
                },
                'type.name' => $type
            },
            { join => 'type' }
        );
    }
    else {                      # no mito genome
        $nuclear_rs = $dbrow->search_related(
            'features',
            { 'type.name' => $type },
            { join        => 'type' }
        );
    }

    $event->logger->logcroak(
        "no reference feature found for organism " . $dbrow->common_name

    ) if !$nuclear_rs->count;

    $event->response($nuclear_rs);

}

sub read_mito_reference {
    my ( $self, $event, $dbrow ) = @_;
    my $rs = $dbrow->search_related(
        'features',
        {   'type.name'   => $self->reference_type,
            'type_2.name' => 'mitochondrial_DNA',
            'cv.name'     => 'sequence'
        },
        { join => [ 'type', { 'featureprops' => { 'type' => 'cv' } } ] }
    );
    $event->logger->logcroak(
        "no mitochondrial reference feature(s) found for organism "
            . $dbrow->common_name )
        if !$rs->count;

    $event->response($rs);
}

sub read_seq_id {
    my ( $self, $event, $dbrow ) = @_;
    my $seq_id = $self->_chado_feature_id($dbrow);
    $event->response_id($seq_id);
}

sub _chado_feature_id {
    my ( $self, $dbrow ) = @_;
    if ( my $dbxref = $dbrow->dbxref ) {
        if ( my $id = $dbxref->accession ) {
            return $id;
        }
    }
    else {
        return $dbrow->uniquename;
    }
}

sub _children_dbrows {
    my ( $self, $parent_row, $relation, $type ) = @_;
    $type = { -like => $type } if $type =~ /^%/;
    return $parent_row->search_related(
        'feature_relationship_objects',
        { 'type.name' => $relation },
        { join        => 'type' }
        )->search_related(
        'subject',
        { 'type_2.name' => $type },
        { join          => 'type' }
        );
}

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



