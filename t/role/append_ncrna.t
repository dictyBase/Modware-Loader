
package TestncRNA;

use autodie qw/close open/;
use File::Temp;
use IO::File;
use IO::String;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use namespace::autoclean;

has 'input' => ( is => 'rw', isa => 'Str' );

has 'ncrna' => (
    is      => 'rw',
    isa     => 'Bool',
    trigger => sub {
        my ($self) = @_;
        $self->meta->make_mutable;
        ensure_all_roles( $self,
            'Modware::Role::Command::GOA::Dicty::AppendncRNA' );
        $self->meta->make_immutable;
    },
    default => 0,
    lazy    => 1
);

# Creating a temp file for the input so that the input doesn't get overwritten
has 'test_input' => (
    is      => 'rw',
    isa     => 'Str',
    trigger => sub {
        my ( $self, $file ) = @_;
        my $handler = IO::File->new( $file, 'r' );
        my $fh = File::Temp->new( unlink => 0 );
        while ( my $line = $handler->getline ) {
            $fh->print($line);
        }
        $self->input( $fh->filename );
        $handler->close;
    }
);

# Just writing input to an output file
sub execute {
    my ( $self, $output ) = @_;
    my $handler = IO::File->new( $self->input, 'r' );
    while ( my $line = $handler->getline ) {
        $output->print($line);
    }
    $handler->close;
    File::Temp->cleanup;
}

with 'Modware::Role::Loggable';

__PACKAGE__->meta->make_immutable;

1;

package main;

use File::Spec::Functions;
use FindBin qw/$Bin/;
use IO::File;
use Module::Build;
use Test::Exception;
use Test::File;
use Test::More qw/no_plan/;
use Test::Moose::More;

my $test = new_ok('TestncRNA');
my $file = catfile( $Bin, '../test_data', 'test_dicty_ncrna.gaf2' );
$test->test_input($file);

does_not_ok(
    $test,
    'Modware::Role::Command::GOA::Dicty::AppendncRNA',
    'does NOT do the AppendncRNA role, if attribute not set'
);

has_method_ok( $test, 'execute' );
$test->ncrna(1);
does_ok(
    $test,
    'Modware::Role::Command::GOA::Dicty::AppendncRNA',
    'does the AppendncRNA role, when attribute is set'
);

file_exists_ok( $test->input );
file_line_count_is( $test->input, 23 );

my $output;
my $handler = IO::File->new( \$output, 'w' );
lives_ok { $test->execute($handler) } 'runs execute method';
$handler->close;

my $reader = IO::File->new( \$output, 'r' );
my $count = 0;
while ( $reader->getline ) { $count++ }
$reader->close;
is( $count, 226, 'it should have 203 additional lines in the output' );
