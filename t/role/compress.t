
package TestCompress;

use autodie qw/close open/;
use Moose;
use Moose::Util qw/ensure_all_roles/;
use namespace::autoclean;

has 'output' => ( is => 'rw', isa => 'Str' );
has 'compress' => (
    is      => 'rw',
    isa     => 'Bool',
    trigger => sub {
        my ($self) = @_;
        $self->meta->make_mutable;
        ensure_all_roles( $self, 'Modware::Role::Command::CanCompress' );
        $self->meta->make_immutable;
    },
    default => 0,
    lazy    => 1
);

sub execute {

}

with 'Modware::Role::Loggable';

__PACKAGE__->meta->make_immutable;

1;

package main;

use File::Spec::Functions;
use FindBin qw/$Bin/;
use Test::Exception;
use Test::File;
use Test::More qw/no_plan/;
use Test::Moose::More;

my $test = new_ok('TestCompress');
my $file = catfile( $Bin, '../test_data', 'test_dicty_ncrna.gaf2' );
$test->output($file);

does_not_ok(
    $test,
    'Modware::Role::Command::CanCompress',
    'does NOT do the CanCompress role, if not called'
);
has_method_ok( $test, 'execute' );
$test->compress(1);
does_ok(
    $test,
    'Modware::Role::Command::CanCompress',
    'does the CanCompress role, if set'
);

file_exists_ok( $test->output );
lives_ok { $test->execute() } 'runs execute method';
file_exists_ok( $test->output . ".gz" );
unlink( $test->output . ".gz" );
file_not_exists_ok( $test->output . ".gz" );
