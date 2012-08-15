package Modware::Report::Command::sumstatsongff3;

use namespace::autoclean;
use Moose;
use File::Temp;
use Bio::DB::SeqFeature::Store;
use Bio::DB::SeqFeature::Store::GFF3Loader;
use List::Util qw/max min/;
use Text::TabularDisplay;
use File::Basename;
use Child;
extends qw/Modware::Report::Command/;

has 'source' => (
    is        => 'rw',
    isa       => 'Str',
    predicate => 'has_source',
    documentation =>
        'GFF3 source field(column 2) to which list of features will be restricted to'
);

has '_stat_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash NoGetopt/],
    lazy    => 1,
    default => sub {
        my $self = shift;
        return {
            intron_stats => sub { $self->intron_stats(@_) }
        };
    },
    handles => {
        get_stat_coderef      => 'get',
        register_stat_coderef => 'set',
        all_stat_coderefs     => 'keys'
    }
);

sub execute {
    my ( $self, $opt, $argv ) = @_;
    my $logger = $self->output_logger;
    $logger->error_die("No input gff[GFF3] file is given") if !@$argv;

    my @child;
    for my $file (@$argv) {
        push @child, Child->new(
            sub {
                $self->generate_stats($file);
            }
        );
    }
    for my $children (@child) {
        my $proc = $children->start;
        $logger->debug( "starting children ", $proc->pid );
    }
    Child->wait_all;
}

sub generate_stats {
    my ( $self, $file ) = @_;
    my $tmpfile = File::Temp->new->filename;
    my $db      = Bio::DB::SeqFeature::Store->new(
        -adaptor => 'DBI::SQLite',
        -dsn     => "dbi:SQLite:dbname=$tmpfile",
        -create  => 1
    );
    my $filename = basename $file;
    my $logger   = $self->output_logger;
    $logger->info("going to store file $filename in temporary storage ....");
    my $loader = Bio::DB::SeqFeature::Store::GFF3Loader->new(
        -store => $db,
        -fast  => 1
    );
    $loader->load($file);
    $logger->info("going to generate summary statistics for $filename....");

    for my $key ( $self->all_stat_coderefs ) {
        my $code = $self->get_stat_coderef($key);
        $code->( $db, $filename );
    }

}

sub intron_stats {
    my ( $self, $db, $filename ) = @_;
    my %opt
        = $self->has_source
        ? ( -type => 'mRNA', -source_tag => $self->source_tag )
        : ( -type => 'mRNA' );

    # stats on introns
    my $itr   = $db->get_seq_stream(%opt);
    my $total = 0;
    my $count = 0;
    my @all_lengths;
TRANS:
    while ( my $trans = $itr->next_seq ) {
        my @exons
            = sort { $a->start <=> $b->start } $db->get_SeqFeatures($trans);
        next TRANS if scalar @exons == 1;
        $count += $#exons;
        my $end = $#exons - 1;
        for my $i ( 0 .. $end ) {
            my $intron_length = $exons[ $i + 1 ]->start - $exons[$i]->end;
            $total += $intron_length;
            push @all_lengths, $intron_length;
        }
    }

    if ( $total and $count ) {
        my $display = Text::TabularDisplay->new(
            qw/File Type Avg(nt) Max(nt) Min(nt)/);
        $display->add( $filename, "intron", int( $total / $count ),
            max(@all_lengths), min(@all_lengths) );
        print $display->render, "\n";
    }
    else {
        $self->output_logger->warn('Unable to retreive any intron stats');
    }
}

1;

__END__

=head1 NAME

Modware::Report::Command::sumstatsongff3 - Generate various summary statistics from gff3 file
