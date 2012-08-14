package Modware::Fetch::Command::publication;
use strict;

# Other modules:
use Moose;
use Time::Piece;
use Email::Valid;
use File::Temp;
use Bio::DB::EUtilities;
use XML::Twig;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use File::Temp;
use File::Spec::Functions;
extends qw/Modware::Fetch::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Command::WithEmail';

# Module implementation
#

has '+input' => ( traits => [qw/NoGetopt/]);

has '+output' => (
    default => sub {
        my $self = shift;
        return catfile( $self->data_dir, 'pubmed_' . $self->date . '.xml' );
    },
    documentation =>
        'It is written in the data_dir folder with the name [ default is pubmed_(current_date).xml]'
);

has 'link_output' => (
    is          => 'rw',
    traits      => [qw/Getopt/],
    cmd_aliases => 'lo',
    isa         => 'Str',
    documentation =>
        'file name where the elink output will be written,  by default it is written under
        the data_dir folder with the name [default is pubmed_links_(current_date) . xml ] ',
    default => sub {
        my $self = shift;
        return catfile( $self->data_dir,
            'pubmed_links_' . $self->date . '.xml' );
    }, 
    lazy => 1
);

has 'temp_file' => (
    is      => 'rw',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    default => sub {
        my $fh = File::Temp->new;
        $fh->filename;
    }
);

has 'genus' => (
    is          => 'rw',
    isa         => 'Str',
    predicate   => 'has_genus',
    traits      => [qw/Getopt/],
    cmd_aliases => 'g',
    required    => 1,
);

has 'species' => (
    is          => 'rw',
    isa         => 'Str',
    traits      => [qw/Getopt/],
    predicate   => 'has_species',
    cmd_aliases => 'sp',
    required    => 1
);

has 'query' => (
    is  => 'rw',
    isa => 'Maybe [Str]',
    documentation =>
        'query for getting the pubmed entries, by default it is [genus] OR [species][tw]',
    default => sub {
        my $self = shift;
        if ( $self->has_genus and $self->has_species ) {
            return $self->genus . ' OR ' . $self->species . '[tw]';
        }
    }, 
    lazy => 1
);

has 'should_get_links' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
    documentation =>
        'flag to indicate if it is going to fetch the elinks, default is true'
);

has 'do_copyright_patch' => (
    is          => 'rw',
    isa         => 'Bool',
    default     => 1,
    traits      => [qw/Getopt/],
    cmd_aliases => 'patch',
    documentation =>
        'flag to indicate to remove the copyright tag from pubmed xml,  default is true'
);

has 'reldate' => (
    is            => 'rw',
    isa           => 'Int',
    default       => 14,
    documentation => 'number of dates preceding todays date, default is 14'
);

has 'retmax' => (
    is            => 'rw',
    isa           => 'Int',
    default       => 100,
    documentation => 'maximum no of entries to return, default is 100'
);

has 'db' => (
    is            => 'rw',
    isa           => 'Str',
    default       => 'pubmed',
    documentation => 'Name of entrez database, default is PubMed'
);

has 'email' => (
    is      => 'rw',
    isa     => 'Email',
    default => 'dictybase@northwestern.edu',
    documentation =>
        'e-mail that will be passed to eutils for fetching default is dictybase@northwestern.edu'
);

has 'date' => (
    is      => 'ro',
    traits  => [qw/NoGetopt/],
    isa     => 'Str',
    default => sub {
        Time::Piece->new->mdy('');
    }
);

sub execute {
    my $self   = shift;
    my $log = $self->dual_logger;
    my $eutils = Bio::DB::EUtilities->new(
        -eutil      => 'esearch',
        -db         => $self->db,
        -term       => $self->query,
        -reldate    => $self->reldate,
        -retmax     => $self->retmax,
        -usehistory => 'y',
        -email      => $self->from
    );
    my $hist = $eutils->next_History || $log->logdie("no history");

    $log->info('got ',  $eutils->get_count,  ' references');

    my @ids = $eutils->get_ids;

    $eutils->reset_parameters(
        -eutils  => 'efetch',
        -db      => $self->db,
        -history => $hist, 
        -email => $self->from
    );

    $eutils->get_Response(
        -file => $self->do_copyright_patch
        ? $self->temp_file
        : $self->output->stringify
    );

    $eutils->reset_parameters(
        -eutil  => 'elink',
        -dbfrom => $self->db,
        -cmd    => 'prlinks',
        -id     => [@ids], 
        -email => $self->from
    );

    $eutils->get_Response( -file => $self->link_output );
    $log->info('done writing elink output');

    if ( $self->do_copyright_patch ) {

#patch to remove the CopyrightInformation node from pubmedxml
#It contains a encoding that causes XML::Parser to throw therefore breaking bioperl parser
        my $twig = XML::Twig->new(
            twig_handlers => {
                'CopyrightInformation' => sub { $_[1]->delete }
            },
            'pretty_print' => 'indented',
        )->parsefile( $self->temp_file );
        $twig->print($self->output_handler);
        $self->output_handler->close;
        $log->info('done patching copyright');
    }

    $log->info('wrote output to file ',  $self->output->stringify);
    $self->subject('weekly pubmed retrieval');
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



