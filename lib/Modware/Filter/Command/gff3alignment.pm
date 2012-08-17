package Modware::Filter::Command::gff3alignment;

use namespace::autoclean;
use Moose;
use Bio::DB::SeqFeature::Store;
use Bio::DB::SeqFeature::Store::GFF3Loader;
use File::Temp;
use Bio::GFF3::LowLevel qw/gff3_format_feature/;
extends qw/Modware::Filter::Command/;

has 'input_gff3' => (
    is      => 'rw',
    traits  => [qw/NoGetopt/],
    isa     => 'IO::Handle',
    trigger => sub {
        my ( $self, $input ) = @_;
        my $tmpfile = File::Temp->new->filename;
        my $db      = Bio::DB::SeqFeature::Store->new(
            -adaptor => 'DBI::SQLite',
            -dsn     => "dbi:SQLite:dbname=$tmpfile",
            -create  => 1
        );

        my $loader = Bio::DB::SeqFeature::Store::GFF3Loader->new(
            -store => $db,
            -fast  => 1
        );
        $loader->load($input);
        $self->gff3db($db);
    }
);

has 'gff3db' => (
    is     => 'rw',
    traits => [qw/NoGetopt/],
    isa    => 'Bio::DB::SeqFeature::Store'
);

has 'match_type' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'protein_match',
    documentation =>
        'SO term used for alignment matches,  defaults to protein_match'
);

has 'match_part_distance' => (
    is       => 'rw',
    isa      => 'Int',
    required => 1,
    documentation =>
        'Cutoff distance for match parts in base pairs. Any match group with a single match part above the cutoff will be filtered'
);

has '_filter_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash NoGetopt/],
    lazy    => 1,
    default => sub {
        my $self = shift;
        return {
            match_part => sub { $self->match_part_filter(@_) }
        };
    },
    handles => {
        get_filter_coderef      => 'get',
        register_filter_coderef => 'set',
        all_filter_coderefs     => 'keys'
    }
);

has '_attribute_stack' => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => [qw/NoGetopt Hash/],
    lazy    => 1,
    default => sub {
        return {
            load_id   => 1,
            parent_id => 1,
            Name      => 1,
            ID        => 1,
            Target    => 1
        };
    },
    handles => { has_tag => 'exists' }
);

sub execute {
    my ($self) = @_;
    my $logger = $self->output_logger;
    $logger->info("going to store input in temporary storage ....");
    $self->input_gff3( $self->input_handler );
    $logger->info("done loading input in temporary storage ....");

    for my $key ( $self->all_filter_coderefs ) {
        my $code = $self->get_filter_coderef($key);
        $code->( $self->gff3db );
    }
    $self->input_handler->close;
    $self->output_handler->close;
}

sub match_part_filter {
    my ( $self, $db ) = @_;
    my $total_match    = 0;
    my $filtered_match = 0;
    my $itr            = $db->get_seq_stream( -type => $self->match_type );
    my $output         = $self->output_handler;

    # -- wrote the header
    $output->print("##gff-version\t3\n");

MATCH:
    while ( my $match = $itr->next_seq ) {
        $total_match++;
        my @parts
            = sort { $a->start <=> $b->start } $db->get_SeqFeatures($match);
        my $end = $#parts - 1;
        for my $i ( 0 .. $end ) {
            my $distance = $parts[ $i + 1 ]->start - $parts[$i]->end;
            if ( $distance > $self->match_part_distance ) {
                next MATCH;
            }
        }
        $self->_write_gff3( [ $match, @parts ] );
    }
}

sub _write_gff3 {
    my ( $self, $features ) = @_;
    my $parent;
    for my $sf (@$features) {
        my $hashref = {};
        $hashref->{seq_id} = $sf->seq_id;
        $hashref->{type}   = $sf->primary_tag;
        $hashref->{source} = $sf->source_tag;
        $hashref->{start}  = $sf->start;
        $hashref->{end}    = $sf->end;
        $hashref->{strand} = undef;
        $hashref->{score}  = $sf->score;

        if (my $strand = $sf->strand ) {
            $hashref->{strand} = $strand == -1 ? '-' : '+';
        }

        if ( $sf->primary_tag eq 'match_part' ) {
            $hashref->{attributes}->{Parent} = [ $parent->load_id ];
        }
        else {
            $hashref->{attributes} = {
                ID   => [ $sf->load_id ],
                Name => [ $sf->name ]
            };
            $parent = $sf;
        }

        if ( $sf->has_tag('Parent') ) {
            my ($p) = $sf->get_tag_values('Parent');
            $hashref->{attributes}->{Parent} = [$p];

        }
        if ( my $target = $sf->target ) {
            my $value = sprintf "%s %d %d",
                $self->_normalize_name( $target->name ),
                $target->start,
                $target->end;
            $hashref->{attributes}->{Target} = [$value];
        }
        for my $tag ( grep { !$self->has_tag($_) } $sf->get_all_tags ) {
            my ($value) = $sf->get_tag_values($tag);
            $hashref->{attributes}->{$tag} = [$value];
        }
        $self->output_handler->print( gff3_format_feature($hashref) );
    }
}

sub _normalize_name {
    my ( $self, $name ) = @_;
    return ( ( split /:/, $name ) )[0];
}

1;

__END__

=head1 NAME

Modware::Filter::Command::gff3alignment - Filter alignment matches from gff3
