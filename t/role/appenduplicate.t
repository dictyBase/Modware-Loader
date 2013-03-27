package TestDuplicate;
use namespace::autoclean;
use Moose;
use IO::String;
use IO::File;
use File::Temp;
use autodie qw/close open/;
use feature qw/say/;

has 'input' => ( is => 'rw', isa => 'Str' );
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
with 'Modware::Role::Command::GOA::Dicty::AppendDuplicate';

__PACKAGE__->meta->make_immutable;
1;

package main;
use Test::More qw/no_plan/;
use FindBin qw/$Bin/;
use Test::Exception;
use Test::File;
use IO::File;
use File::Spec::Functions;

my $test = new_ok('TestDuplicate');
$test->test_input( catfile( $Bin, '../test_data', 'testdicty.gaf2' ) );

file_exists_ok( $test->input );
file_line_count_is( $test->input, 14 );

my $output;
my $handler = IO::File->new( \$output, 'w' );
lives_ok { $test->execute($handler) } 'it runs the execute method';
$handler->close;

my $reader = IO::File->new( \$output, 'r' );
my $count = 0;
while (<$reader>) { $count++ }
$reader->close;
is( $count, 49, 'it should have 29 lines in the output' );
