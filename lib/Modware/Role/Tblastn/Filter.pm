package Modware::Role::Tblastn::Filter;

# Other modules:
use namespace::autoclean;
use Moose::Role;

# Module implementation
#
has '_context_map' => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub {
        return {
            '+0' => 'p1',
            '+1' => 'p2',
            '+2' => 'p3',
            '-0' => 'm1',
            '-1' => 'm2',
            '-2' => 'm3'
        };
    },
    handles => { 'get_frame_context' => 'get' }
);

has '_hit_context_map' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub {
        return {};
    },
    lazy    => 1,
    handles => {
        'get_hit_by_context'    => 'get',
        'set_hit_with_context'  => 'set',
        'clear_hit_context'     => 'clear',
        'all_hits_with_context' => 'values'
    }
);

has '_hit_counter' => (
    is      => 'rw',
    isa     => 'Num',
    traits  => [qw/Counter/],
    default => 0,
    lazy    => 1,
    handles => {
        'inc_hit_count'   => 'inc',
        'reset_hit_count' => 'reset'
    }
);

has 'global_hit_counter' => (
    is      => 'rw',
    isa     => 'Num',
    traits  => [qw/NoGetopt Counter/],
    default => 1,
    lazy    => 1,
    handles => { 'inc_global_hit_count' => 'inc', }
);

sub split_hit_by_strand {
    my ( $self, $old_result, $new_result ) = @_;

HIT:
    while ( my $hit = $old_result->next_hit ) {
        my $hname
            = $self->hit_id_parser
            ? $self->get_parser( $self->hit_id_parser )->( $hit->name )
            : $hit->name;
        my $hacc = $hit->accession ? $hit->accession : $hname;

        my $plus_hit = Bio::Search::Hit::GenericHit->new(
            -name      => $hname . '-match-plus' . $self->global_hit_counter,
            -accession => $hacc,
            -algorithm => $hit->algorithm,
        );
        my $minus_hit = Bio::Search::Hit::GenericHit->new(
            -name      => $hname . '-match-minus' . $self->global_hit_counter,
            -accession => $hacc,
            -algorithm => $hit->algorithm,
        );

        for my $hsp ( $hit->hsps ) {
            if ( $hsp->strand('hit') == -1 ) {
                $hsp->hit->display_name( $minus_hit->name );
                $minus_hit->add_hsp($hsp);
            }
            else {
                $hsp->hit->display_name( $plus_hit->name );
                $plus_hit->add_hsp($hsp);
            }
        }
        $new_result->add_hit($plus_hit)  if $plus_hit->num_hsps  =~ /^\d+$/;
        $new_result->add_hit($minus_hit) if $minus_hit->num_hsps =~ /^\d+$/;

        $self->inc_global_hit_count;
    }
}

sub split_hit_by_strand_and_frame {
    my ( $self, $old_result, $new_result ) = @_;

HIT:
    while ( my $hit = $old_result->next_hit ) {
        my $hname
            = $self->hit_id_parser
            ? $self->get_parser( $self->hit_id_parser )->( $hit->name )
            : $hit->name;
        my $hacc = $hit->accession ? $hit->accession : $hname;

       # first we stack all possible hits with all possible strands and frames
       # combinations
        for my $strand (qw/p m/) {
            for my $frame ( 1 .. 3 ) {
                my $context = $strand . $frame;
                my $hit     = Bio::Search::Hit::GenericHit->new(
                    -name => $hname . '-' 
                        . $context . '.'
                        . $self->global_hit_counter,
                    -accession => $hacc,
                    -algorithm => $hit->algorithm,
                );
                $self->set_hit_with_context( $context => $hit );
            }
        }

        # here we sort the hsp based on their strand and frame combinations
    HSP:
        for my $hsp ( $hit->hsps ) {
            my $strand = $hsp->strand('hit') == 1 ? '+' : '-';
            my $frame_context
                = $self->get_frame_context( $strand . $hsp->frame('hit') );
            my $context_hit = $self->get_hit_by_context($frame_context);
            next HSP if !$context_hit;
            $hsp->hit->display_name( $context_hit->name );
            $context_hit->add_hsp($hsp);
        }

    CHIT:
        for my $newhit ( $self->all_hits_with_context ) {
            next CHIT if $newhit->num_hsps !~ /^\d+$/;
            $new_result->add_hit($newhit);
        }
        $self->inc_global_hit_count;
        $self->clear_hit_context;
    }
}

sub split_hit_by_intron_length {
    my ( $self, $old_result, $new_result, $intron_length ) = @_;
    my $coderef = sub {
        my ( $hsp_current, $hsp_next, $length ) = @_;
        my $distance = $hsp_next->start('hit') - $hsp_current->end('hit');
        return 1 if $distance > $length;
    };
    $self->_split_hit( $old_result, $new_result, $coderef, $intron_length );
}

sub split_overlapping_hit {
    my ( $self, $old_result, $new_result ) = @_;
    my $coderef = sub {
        my ( $current_hsp, $next_hsp ) = @_;
        if (    ( $current_hsp->end('hit') >= $next_hsp->start('hit') )
            and ( $current_hsp->end('hit') <= $next_hsp->end('hit') ) )
        {
            return 1;
        }
    };
    $self->_split_hit( $old_result, $new_result, $coderef );
}

sub _split_hit {
    my ( $self, $old_result, $new_result, $coderef, $param ) = @_;
HIT:
    while ( my $old_hit = $old_result->next_hit ) {
        my @hsps
            = sort { $a->start('hit') <=> $b->start('hit') } $old_hit->hsps;
        if ( @hsps == 1 ) {
            $new_result->add_hit($old_hit);
            next HIT;
        }

# array of hsp array
# [ ['hsp', 'hsp',  'hsp' ...],  ['hsp', 'hsp' ....], ['hsp',  'hsp',  'hsp' ...]]
        my $hsp_stack;

        # the index in the hsp stack where the next hsp should go
        my $index = 0;

     # the index of the hsp that is already been pushed into the new hsp stack
        my $pointer = {};
        for my $i ( 0 .. $#hsps - 1 ) {
            if ( not exists $pointer->{$i} ) {
                push @{ $hsp_stack->[$index] }, $hsps[$i];
                $pointer->{$i} = 1;
            }

            # coderef decides if the hsp stays in the current position
            my $return = $coderef->( $hsps[$i], $hsps[ $i + 1 ], $param );
            $index++ if $return;
            push @{ $hsp_stack->[$index] }, $hsps[ $i + 1 ];
            $pointer->{ $i + 1 } = 1;
        }

        if ( @$hsp_stack == 1 ) {
            $new_result->add_hit($old_hit);
        }
        else {
            for my $i ( 0 .. $#$hsp_stack ) {
                my $new_hit
                    = $self->clone_hit( $old_hit, $self->inc_hit_count );
                for my $new_hsp ( @{ $hsp_stack->[$i] } ) {
                    $new_hsp->hit->display_name( $new_hit->name );
                    $new_hit->add_hsp($new_hsp);
                }
                $new_result->add_hit($new_hit);
            }
            $self->reset_hit_count;
        }
    }
}

sub has_start_codon {
    my ( $self, $hit ) = @_;
    my @hsps = sort { $a->start('query') <=> $b->start('query') } $hit->hsps;
    my $qaa = substr $hsps[0]->query_string, 0, 1;
    my $haa = substr $hsps[0]->hit_string,   0, 1;

    if ( ( $qaa eq 'M' ) and ( $haa eq 'M' ) ) {
        return 1;
    }
}

sub has_stop_codon {
    my ( $self, $hit ) = @_;
    while ( my $hsp = $hit->next_hsp ) {
        return if $hsp->hit_string =~ /\*/;
    }
    return 1;
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



