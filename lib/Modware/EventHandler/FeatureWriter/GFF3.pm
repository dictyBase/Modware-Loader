package Modware::EventHandler::FeatureWriter::GFF3;

# Other modules:
use namespace::autoclean;
use Moose;

# Module implementation
#

has 'output' => (
    is  => 'rw',
    isa => 'IO::Handle'
);

sub write_header {
    my ( $self, $event ) = @_;
    $self->output->print("##gff-version\t3\n");
}

sub write_meta_header {
    my ( $self, $event ) = @_;
}

sub write_sequence_region {
    my ( $self, $event, $seq_id, $dbrow ) = @_;
    my $output = $self->output;

    if ( my $end = $dbrow->seqlen ) {
        $output->print("##sequence-region\t$seq_id\t1\t$end\n");
    }
    elsif ( my $length = $dbrow->get_column('sequence_length') ) {
        $output->print("##sequence-region\t$seq_id\t1\t$length\n");
    }
    else {
        $event->warn("$seq_id has no length defined:skipped from export");
    }

}

sub _dbrow2gff3hash {
    my ( $self, $dbrow, $event, $seq_id, $parent_id, $parent ) = @_;
    my $hashref;
    $hashref->{type}   = $event->get_cvrow_by_id( $dbrow->type_id )->name;
    $hashref->{score}  = undef;
    $hashref->{seq_id} = $seq_id;

    my $floc_row = $dbrow->featureloc_features->first;
    $hashref->{start} = $floc_row->fmin + 1;
    $hashref->{end}   = $floc_row->fmax;
    if ( my $strand = $floc_row->strand ) {
        $hashref->{strand} = $strand == -1 ? '-' : '+';
    }
    else {
        $hashref->{strand} = undef;
    }

    if ( $hashref->{type} eq 'CDS' ) {
        ## -- phase for CDS
    }
    else {
        $hashref->{phase} = undef;
    }

    # source
    my $dbxref_rs
        = $dbrow->search_related( 'feature_dbxrefs', {} )->search_related(
        'dbxref',
        { 'db.name' => 'GFF_source' },
        { join      => 'db' }
        );
    if ( my $row = $dbxref_rs->first ) {
        $hashref->{source} = $row->accession;
    }
    else {
        $hashref->{source} = undef;
    }

    ## -- attributes
    $hashref->{attributes}->{ID} = [ $self->_chado_feature_id($dbrow) ];
    if ( my $name = $dbrow->name ) {
        $hashref->{attributes}->{Name} = [$name];
    }
    $hashref->{attributes}->{Parent} = [$parent_id] if $parent_id;
    my $dbxrefs;
    for my $xref_row (
        grep { $event->get_dbrow_by_id( $_->db_id )->name ne 'GFF_source' }
        $dbrow->secondary_dbxrefs )
    {
        my $dbname = $event->get_dbrow_by_id( $xref_row->db_id )->name;
        $dbname =~ s/^DB:// if $dbname =~ /^DB:/;
        push @$dbxrefs, $dbname . ':' . $xref_row->accession;
    }
    $hashref->{attributes}->{Dbxref} = $dbxrefs if  @$dbxrefs;
    return $hashref;
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

sub gff_source {
    my ( $self, $dbrow ) = @_;
    my $dbxref_rs
        = $dbrow->search_related( 'feature_dbxrefs', {} )->search_related(
        'dbxref',
        { 'db.name' => 'GFF_source' },
        { join      => 'db' }
        );
    if ( my $row = $dbxref_rs->first ) {
        return $row->accession;
    }
}

sub setup_feature_location {
    my ( $self, $event, $dbrow, $hashref ) = @_;
    $hashref->{start}  = $dbrow->fmin + 1;
    $hashref->{end}    = $dbrow->fmax;
    $hashref->{strand} = $dbrow->strand == -1 ? '-' : '+';
}

sub setup_subfeature_location {
    my ( $self, $event, $dbrow, $hashref ) = @_;
    $hashref->{start}  = $dbrow->fmin + 1;
    $hashref->{end}    = $dbrow->fmax;
    $hashref->{strand} = $dbrow->strand == -1 ? '-' : '+';
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



