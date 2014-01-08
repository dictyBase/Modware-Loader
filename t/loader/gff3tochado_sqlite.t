use Test::More;
use File::Spec::Functions;
use FindBin qw/$Bin/;
use Path::Class::Dir;
use lib catdir( $Bin, '..', 'lib' );
use ChadoGFF3CmdLineRunner;

my $input
    = Path::Class::Dir->new($Bin)->parent->subdir('test_data')->subdir('gff3')
    ->file('test1.gff3')->stringify;
ChadoGFF3CmdLineRunner->run_tests( { input => $input, backend => 'sqlite' } );
done_testing;
