package discoideum::gff3::individual;

use Getopt::Long::Descriptive;
use Cwd;
use Modware::Export;
use File::Spec::Functions;
use Child qw/child/;
use YAML qw/LoadFile/;
use List::MoreUtils qw/natatime/;

my ( $opt, $usage ) = describe_options(
    '%c %o',
    [   'config|c=s',
        'yaml config file specifying database credentials',
        { required => 1 }
    ],
    [   'output-folder:s',
        'folder where gff3 will be written,  default is the running folder',
        { default => getcwd() }
    ],
    [   'chromosome:@',
        'List of discoideum chromosome names that will be exported,  default is all of them',
        { default => [qw/1 2 3 4 5 6 BF 2F 3F M R/] }
    ],
    [   'num-parallel:i',,
        'Number of exports to run in parallel, default is 3',
        { default => 3 }
    ], 
    [ 'help|h', 'print this help' ]
);

$usage->die if $opt->help;

my $cmd_name = 'chado2dictycanonicalgff3';
my $config   = LoadFile( $opt->config );
my $config_opts;
push @$config_opts, '--' . $_, $config->{$_} for keys %$config;

# generate the command lines
my $cmdlines;
for my $chr ( @{ $opt->chromosomes } ) {
    push @$cmdlines,
        [
        $cmd_name, @$config_opts, '--feature_name', 1, '--reference_id',
        $chr, '--output',
        catfile( $opt->output_folder, 'canonical-' . $chr . '.gff3' )
        ];
}

#fork and run
my $it = natatime, $opt->num_parallel, @$cmdlines;
while ( my @group = $it->() ) {
    for my $arg (@group) {
        my $proc = child {
            my $cmd = Modware::Export->new;
            local @ARGV = @$arg;
            $cmd->run;
        };
        say 'started child ', $proc->pid;
    }
    Child->wait_all;
}

=head1 NAME

discoideum-split-canonical - Export canonical GFF3 file into individual chromosome 

