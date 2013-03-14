package Modware::EventHandler::FeatureWriter::GFF3::Alignment;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::GFF3::LowLevel qw/gff3_format_feature/;
extends 'Modware::EventHandler::FeatureWriter::GFF3';

# Module implementation
#

has 'write_aligned_parts' =>
    ( is => 'rw', isa => 'Bool', lazy => 1, default => 1 );

has 'match_type' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'match',
    lazy    => 1
);

has [ 'force_name', 'force_description' ] => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1
);

has '_prop_stack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    lazy    => 1,
    default => sub { [] },
    handles => {
        add_property      => 'push',
        all_properties    => 'elements',
        num_of_properties => 'count'
    }
);

sub write_feature {
    my ( $self, $event, $seq_id, $dbrow ) = @_;

    my $output = $self->output;
    my $hashref;
    $hashref->{seq_id} = $seq_id;
    $hashref->{source} = $self->gff_source($dbrow) || undef;

    $hashref->{type} = $self->match_type;

    my $floc_rs = $dbrow->featureloc_features( { rank => 0 } );
    my $floc_row;
    if ( $floc_row = $floc_rs->first ) {
    	$self->setup_feature_location($event, $floc_row, $hashref);
    }
    else {
        $event->output_logger->log(
            "No feature location relative to genome is found: Skipped from output"
        );
        return;
    }
    $hashref->{phase} = undef;

    my $analysis_rs = $dbrow->search_related( 'analysisfeatures', {} );
    if ( my $row = $analysis_rs->first ) {
        $hashref->{score} = $row->significance;
    }
    else {
        $hashref->{score} = undef;
    }

    my $id = $self->_chado_feature_id($dbrow);
    $hashref->{attributes}->{ID} = [$id];
    if ( my $name = $dbrow->name ) {
        $hashref->{attributes}->{Name} = [$name];
    }
    else {
        $hashref->{attributes}->{Name} = [$id] if $self->force_name;
    }

    if ( $self->force_description ) {
        my $prop_row = $dbrow->search_related(
            'featureprops',
            { 'type.name' => 'description' },
            {   join => 'type',
                rows => 1
            }
        )->single;
        $hashref->{attributes}->{Note} = [ $prop_row->value ] if $prop_row;
    }
    if ( $self->num_of_properties ) {
        my $rs = $dbrow->search_related(
            'featureprops',
            { 'type.name' => { -in => [ $self->all_properties ] } },
            { join        => 'type' }
        );
        for my $row ( $rs->all ) {
            if ( $row->type->name ~~ [$self->all_properties] ) {
                $hashref->{attributes}->{ $row->type->name }
                    = [ $row->value ];
            }
        }
    }

    if ( $self->write_aligned_parts )
    {    ## -- target attribute will be added in the feature parts
        $output->print( gff3_format_feature($hashref) );
        return;
    }

    my $target = $id;
    my $floc2_rs = $dbrow->featureloc_features( { rank => 1 } );
    if ( my $row = $floc2_rs->next ) {
        $target .= "\t" . ( $row->fmin + 1 ) . "\t" . $row->fmax;
        if ( my $strand = $row->strand ) {
            $strand = $strand == -1 ? '-' : '+';
            $target .= "\t$strand";
        }
    }
    else {
        $event->output_logger->warn(
            "No feature location relative to itself(query) is found");
        $event->output_logger->warn("Skipped target attribute from output");
        $output->print( gff3_format_feature($hashref) );
        return;

    }
    $hashref->{attributes}->{Target} = [$target];

    if ( my $gap_str = $floc_row->residue_info ) {
        $hashref->{attributes}->{Gap} = [$gap_str];
    }
    $output->print( gff3_format_feature($hashref) );
}

sub write_subfeature {
    my ( $self, $event, $seq_id, $parent, $dbrow ) = @_;
    my $output    = $self->output;
    my $source    = $self->gff_source($parent) || undef;
    my $parent_id = $self->_chado_feature_id($parent);

    my $hashref;
    $hashref->{seq_id} = $seq_id;
    $hashref->{type}   = 'match_part';
    $hashref->{source} = $source;

    my $floc_rs = $dbrow->featureloc_features( { rank => 0 },
        { order_by => { -asc => 'fmin' } } );
    my $floc_row;
    if ( $floc_row = $floc_rs->first ) {
    	$self->setup_feature_location($event, $floc_row, $hashref);
    }
    else {
        $event->output_logger->warn(
            "No feature location relative to genome is found: Skipped from output"
        );
        return;
    }
    $hashref->{phase}                = undef;
    $hashref->{attributes}->{ID}     = [ $self->_chado_feature_id($dbrow) ];
    $hashref->{attributes}->{Parent} = [$parent_id];

    my $target = $parent_id;
    my $floc2_rs = $dbrow->featureloc_features( { rank => 1 } );
    if ( my $row = $floc2_rs->next ) {
        $target .= "\t" . ( $row->fmin + 1 ) . "\t" . $row->fmax;
        if ( my $strand = $row->strand ) {
            $strand = $strand == -1 ? '-' : '+';
            $target .= "\t$strand";
        }
    }
    else {
        $event->output_logger->warn(
            "No feature location relative to itself(query) is found");
        $output->print( gff3_format_feature($hashref) );
        return;
    }
    $hashref->{attributes}->{Target} = [$target];

    if ( my $gap_str = $floc_row->residue_info ) {
        $hashref->{attributes}->{Gap} = [$gap_str];
    }
    $output->print( gff3_format_feature($hashref) );

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



