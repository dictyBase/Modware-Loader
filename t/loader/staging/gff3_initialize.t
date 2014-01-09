use File::Spec::Functions;
use FindBin qw/$Bin/;
use Test::More;
use Modware::Spec::GFF3::Analysis;
use lib catdir( $Bin, '..', '..', 'lib' );
use StagingGFF3Runner;

StagingGFF3Runner->run_tests(
    {   backend       => 'sqlite',
        analysis_spec => Modware::Spec::GFF3::Analysis->new(
            name           => 'Gene prediction',
            program        => 'geneid',
            programversion => '1.1'
        )
    }
);
done_testing;
