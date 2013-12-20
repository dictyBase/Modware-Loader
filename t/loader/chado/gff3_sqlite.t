use Test::More ;
use File::Spec::Functions;
use FindBin qw/$Bin/;
use lib catdir( $Bin, '..', '..', 'lib' );
use ChadoGFF3Runner;
use ChadoGFF3UpdateRunner;

ChadoGFF3Runner->run_tests({backend => 'sqlite'});
ChadoGFF3UpdateRunner->run_tests({backend => 'sqlite'});
done_testing;


