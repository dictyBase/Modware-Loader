
use File::Spec::Functions;
use FindBin qw/$Bin/;
use IO::File;
use Test::More qw/no_plan/;

my $file = catfile( $Bin, '../test_data', 'dicty_validate.gaf2' );
my $fh = IO::File->new( $file, 'r' );

my $num_entries     = 0;
my $sum_of_cols     = 0;
my $length_of_col16 = 0;
while ( my $line = $fh->getline ) {
    my @cols = split( /\t/, $line );
    $sum_of_cols     += scalar @cols;
    $num_entries     += 1;
    $length_of_col16 += length( $cols[15] );
}

is( $sum_of_cols / $num_entries, 17, "has 17 columns" );
is( $length_of_col16,            0,  'Column 16 is empty' );

