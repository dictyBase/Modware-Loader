package Modware::EventHandler::FeatureWriter::GFF3::Canonical::Dicty;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::GFF3::LowLevel qw/gff3_format_feature/;
extends 'Modware::EventHandler::FeatureWriter::GFF3::Canonical';

has '_gene_cache' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub { {} },
    handles => {
        has_gene_in_cache => 'exists',
        add_gene_in_cache => 'set'
    }
);

# Module implementation
#
sub write_gene {
    return;
}

sub write_transcript {
    my ( $self, $event, $seq_id, $parent_dbrow, $dbrow ) = @_;
    my $output  = $self->output;
    my $gene_id = $self->_chado_feature_id($parent_dbrow);
    my $term;

    #check cache
    if ($event->has_cvrow_id($dbrow->type_id)) {
    	$term = $event->get_cvrow_by_id($dbrow->type_id)->name;
    }
    else { #if not fills it up
    	$term = $dbrow->type->name;
    	$event->set_cvrow_by_id($dbrow->type_id, $dbrow->type);
    }

    if ( $term eq 'pseudogene' ) {

        # dicty pseudogene gene model have to be SO complaint
        # it writes gene and transcript feature
        if ( !$self->has_gene_in_cache($gene_id) ) {
            my $pseudogene_hash
                = $self->pseudorow2gff3hash( $parent_dbrow, $seq_id, '',
                'pseudogene' );
            $output->print( gff3_format_feature($pseudogene_hash) );
            $self->add_gene_in_cache($gene_id,  1);
        }
        my $trans_hash = $self->pseudorow2gff3hash( $dbrow, $seq_id, $gene_id,
            'pseudogenic_transcript' );
        $output->print( gff3_format_feature($trans_hash) );
    }
    else {

        if ( !$self->has_gene_in_cache($gene_id) ) {
            my $gene_hash = $self->_dbrow2gff3hash( $parent_dbrow, $event,  $seq_id );
            $output->print( gff3_format_feature($gene_hash) );
            $self->add_gene_in_cache($gene_id, 1);
        }

        #transcript
        my $trans_hash = $self->_dbrow2gff3hash( $dbrow, $event, $seq_id, $gene_id );
        $output->print( gff3_format_feature($trans_hash) );
    }
}

sub write_exon {
    my ( $self, $event, $seq_id, $parent_dbrow, $dbrow ) = @_;
    my $output   = $self->output;
    my $trans_id = $self->_chado_feature_id($parent_dbrow);
    my $hash;
    if ( $event->get_cvrow_by_id($parent_dbrow->type_id)->name eq 'pseudogene' ) {
        $hash = $self->pseudorow2gff3hash( $dbrow, $seq_id, $trans_id,
            'pseudogenic_exon' );
    }
    else {
        $hash = $self->_dbrow2gff3hash( $dbrow, $event,  $seq_id, $trans_id );
    }
    $output->print( gff3_format_feature($hash) );
}

sub pseudorow2gff3hash {
    my ( $self, $dbrow, $seq_id, $parent_id, $type ) = @_;
    my $hashref;
    $hashref->{type}   = $type;
    $hashref->{seq_id} = $seq_id;
    $hashref->{score}  = undef;
    $hashref->{phase}  = undef;

    my $floc_row = $dbrow->featureloc_features->first;
    $hashref->{start} = $floc_row->fmin + 1;
    $hashref->{end}   = $floc_row->fmax;
    if ( my $strand = $floc_row->strand ) {
        $hashref->{strand} = $strand == -1 ? '-' : '+';
    }
    else {
        $hashref->{strand} = undef;
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
    for my $xref_row ( grep { $_->db->name ne 'GFF_source' }
        $dbrow->secondary_dbxrefs )
    {
        my $dbname = $xref_row->db->name;
        $dbname =~ s/^DB:// if $dbname =~ /^DB:/;
        push @$dbxrefs, $dbname . ':' . $xref_row->accession;
    }
    $hashref->{attributes}->{Dbxref} = $dbxrefs if @$dbxrefs;
    return $hashref;
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



