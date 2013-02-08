
package TestncRNA;

use autodie qw/close open/;
use File::Temp;
use IO::File;
use IO::String;
use Moose;
use namespace::autoclean;

has 'input' => ( is => 'rw', isa => 'Str' );

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
with 'Modware::Role::Command::GOA::Dicty::AppendncRNA';

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

my $test = new_ok('TestncRNA');
my $file = catfile( $Bin, '../data', 'test_dicty.gaf' );
$test->test_input($file);

file_exists_ok( $test->input );
file_line_count_is( $test->input, 23 );

my $output;
my $handler = IO::File->new( \$output, 'w' );
lives_ok { $test->execute($handler) } 'Running execute method';
$handler->close;

my $reader = IO::File->new( \$output, 'r' );
my $count = 0;
while ( $reader->getline ) { $count++ }
$reader->close;
is( $count, 226, 'it should have 203 additional lines in the output' );
