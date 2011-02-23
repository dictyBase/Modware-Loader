package Modware::Transform::Command::goa2modgaf;

# Other modules:
use Moose;
use Moose::Util qw/ensure_all_roles/;
extends qw/Modware::Transform::Command/;
with 'Modware::Role::Command::WithIO';
with 'Modware::Role::Command::WithLogger';

# Module implementation
#

has '+input' => (documentation => 'input GAF file from GOA project');

has 'location' => (
    is        => 'rw',
    isa       => 'Str',
    predicate => 'has_location',
    required  => 1,
    documentation =>
        'Full url/path to a resource that will be used by the converter for id translation. By default is expect a gp2protein file'
);

has 'converter' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'gp2protein',
    documentation =>
        'The converter to use for id translation,  default is gp2protein'
);

has 'namespace' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'Modware::Role::Command::Convert::Resource',
    documentation =>
        'Base namespace for converter roles,  default is Modware::Role::Command::Convert::Resource'
);

sub load_converter {
    my ($self) = @_;
    my $conv_role = $self->namespace . '::' . lc $self->converter;
    $self->meta->make_mutable;
    ensure_all_roles( $self, $conv_role );
    ensure_all_roles( $self, 'Modware::Role::Command::Convert::Identifier' );
    $self->meta->make_immutable;
}

sub execute {
    my ($self) = @_;
    $self->load_converter;

    my $converted     = 0;
    my $not_converted = 0;
    my $total = 0;

    my $input  = $self->input_handler;
    my $output = $self->output_handler;
    my $logger = $self->logger;

LINE:
    while ( my $line = $input->nextline ) {
        if ( $line =~ /^\!/ ) {    ## -- skip header
            $output->print($line);
            next LINE;
        }
        $total++;
        my @data = split /\t/, $line;
        if ( my $mod_id = $self->convert( $data[1] ) ) {
            $data[1] = $mod_id;
            $output->print( join( "\t", @data ) );
            $converted++;
            next LINE;
        }

        $logger->warn("Unable to convert id $data[1]");
        $not_converted++;
    }

    $input->close;
    $output->close;

    $logger->info("total:$total converted:$converted not_converted:$not_converted");

}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

B<goa2modgaf> - [Generates a mod specific gaf file from GOA by converting uniprot to its
canonical id]


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



