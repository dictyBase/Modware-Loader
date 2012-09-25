#!/usr/bin/perl -w

use strict;
use Getopt::Long::Descriptive;
use Cwd;
use Modware::Transform;
use File::Spec::Functions;
use Child;

my ( $opt, $usage ) = describe_options(
    '%c %o',
    [   'input-folder=s',
        'input folder to look for tblastn output',
        { required => 1 }
    ],
    [   'output-folder:s',
        'folder where gff3 will be written,  default is the running folder',
        { default => getcwd() }
    ],
    [   'genomes:s',
        'list of genomes for which the conversion will be run,  default to purpureum, fasciculatum and pallidum',
        { default => [qw/purpureum fasciculatum pallidum/] }
    ],
    [ 'help|h', 'print this help' ]
);

$usage->die if $opt->help;

# generate the command lines
my $cmdlines;
for my $genome ( @{ $opt->genomes } ) {
    my $input
        = catfile( $opt->input_folder, $genome, 'discoideum_tblastn.xml' );
    die "$input do not exist !!!!!\n" if !-e $input;

    my $outfolder = catdir($opt->output_folder, $genome);
    die "$outfolder do not exist !!!!\n" if !-e $outfolder;
    my $output
        = catfile( $outfolder, 'discoideum_tblastn.gff3' );

    push @$cmdlines,
        [
        'blast2gbrowsegff3',   '--input',
        $input,                '--output',
        $output,               '--merge_contained',
        '--remove_stop_codon', '--max_intron_length',
        3000,                  '--format',
        'blastxml',            '--query_id_parser',
        'general',             '--desc_parser',
        'ncbi',                '--source',
        'tblastn.dictyBase'
        ];
}

#make all child
my @child;
for my $arg(@$cmdlines) {
	push @child, Child->new(sub {
		my $cmd = Modware::Transform->new;
		local @ARGV = @$arg;
		$cmd->run;
	});
}


#fork and run
for my $children(@child) {
	my $proc = $children->start;
	warn "starting children ", $proc->pid, "\n";
}

Child->wait_all;

=head1 NAME

discoideum_tblastn_filter - [runs blast2gbrowsegff3 application in parallel for multiple genomes]


