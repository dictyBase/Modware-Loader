package Modware::Transform::Command::blast2gbrowsegff3;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::SearchIO;
use Bio::Search::Result::GenericResult;
use Bio::Search::Hit::GenericHit;
use Bio::GFF3::LowLevel qw/gff3_format_feature/;
use Modware::SearchIO::Blast;
extends qw/Modware::Transform::Command/;

has 'merge_contained' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
    lazy    => 1,
    documentation =>
        'Merge HSPs where both of their endpoints are completely contained within other. The merged HSP will retain attributes of the largest one,  default is true'
);

has 'max_intron_length' => (
    is      => 'rw',
    isa     => 'Int',
    default => 0,
    lazy    => 1,
    documentation =>
        'Max intron length threshold for spliting hsps into separate hit groups,  only true for TBLASTN,  default in none.'
);

has 'format' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'blast',
    lazy    => 1,
    documentation =>
        'Type of blast output,  either blast(text) or blastxml. For blastxml format the query name is parsed from query description'
);

has '+input' =>
    ( documentation => 'blast result file if absent reads from STDIN' );
has 'source' => (
    is          => 'rw',
    isa         => 'Str',
    traits      => [qw/Getopt/],
    cmd_aliases => 's',
    lazy        => 1,
    default     => sub {
        my ($self) = @_;
        return lc $self->_result_object->algorithm;
    },
    documentation =>
        'the source field of GFF output,  default will the algorithm name'
);

has 'primary_tag' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $algorithm = lc $self->_result_object->algorithm;
        my $tag;
        if ( $algorithm eq 'blastn' ) {
            $tag = 'nucleotide_match';
        }
        elsif ( $algorithm eq 'blastp' ) {
            $tag = 'protein_match';
        }
        elsif ( $algorithm eq 'tblastn' ) {
            $tag = 'protein_match';
        }
        else {
            $tag = 'translated_nucleotide_match';
        }
        return $tag;
    },
    documentation =>
        'The type of feature(column3) that will be used for grouping, by default it will be guessed from the blast algorithm',

);

has '_hit_counter' => (
    is      => 'rw',
    isa     => 'Num',
    traits  => [qw/Counter/],
    default => 0,
    lazy    => 1,
    handles => {
        'inc_hit_count'   => 'inc',
        'reset_hit_count' => 'reset'
    }
);

has 'global_hit_counter' => (
    is      => 'rw',
    isa     => 'Num',
    traits  => [qw/NoGetopt Counter/],
    default => 1,
    lazy    => 1,
    handles => { 'inc_global_hit_count' => 'inc', }
);

has '_result_object' => (
    is        => 'rw',
    isa       => 'Bio::Search::Result::GenericResult',
    predicate => 'has_result_object'
);

has 'hit_id_parser' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'hit id parser for the header line,  default is to use none. ncbi_gi, regular and general parsers are available'
);

has 'query_id_parser' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'query id parser for the header line,  default is to use none. ncbi_gi , regular and general parsers are available'
);

has 'desc_parser' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'description parser for the header line,  default is to use none. ncbi parser is available'
);

has '_desc_parser_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => {
        get_desc_parser      => 'get',
        register_desc_parser => 'set',
    },
    default => sub {
        my ($self) = @_;
        return { 'ncbi' => sub { $self->ncbi_desc_parser(@_) }, };
    },
    lazy => 1
);

has '_parser_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => {
        get_parser      => 'get',
        register_parser => 'set',
    },
    default => sub {
        my ($self) = @_;
        return {
            'ncbi'    => sub { $self->ncbi_gi_parser(@_) },
            'regular' => sub { $self->regular_parser(@_) },
            'general' => sub { $self->general_parser(@_) }
        };
    },
    lazy => 1
);

sub ncbi_gi_parser {
    my ( $self, $string ) = @_;
    return $string if $string !~ /\|/;
    return ( ( split /\|/, $string ) )[1];
}

sub regular_parser {
    my ( $self, $string ) = @_;
    return $string if $string !~ /\|/;
    return ( ( split /\|/, $string ) )[0];
}

sub general_parser {
    my ( $self, $string ) = @_;
    return $string if $string !~ /\|/;
    return ( ( split /\|/, $string ) )[2];
}

sub ncbi_desc_parser {
    my ( $self, $string ) = @_;
    return $string if $string !~ /\|/;
    my @values = ( split /\|/, $string );
    my $desc = $values[-1];
    $desc =~ s/^\s*//g;
    $desc =~ s/\s*$//g;
    return $desc;
}

sub execute {
    my ($self) = @_;
    my $parser = Modware::SearchIO::Blast->new(
        format => $self->format,
        file   => $self->input_handler
    );
    $self->output_handler->print("##gff-version\t3\n");

    $parser->subscribe( 'filter_result' => sub { $self->filter_result(@_) } );
    $parser->subscribe( 'write_result'  => sub { $self->write_result(@_) } );
    $parser->subscribe( 'write_hit'     => sub { $self->write_hit(@_) } );
    $parser->subscribe( 'write_hsp'     => sub { $self->write_hsp(@_) } );
    $parser->subscribe( 'filter_hit'    => sub { $self->filter_hit(@_) } )
        if $self->merge_contained;

    $parser->process;
}

#extract query accession, name and description from result object
# and split hits in case of tblastn

sub filter_result {
    my ( $self, $event, $result ) = @_;

    # construct a fresh result object
    my $new_result = Bio::Search::Result::GenericResult->new;
    $self->normalize_result_names( $result, $new_result );
    $self->clone_minimal_result_fields( $result, $new_result );

  #additional grouping of hsp's by the hit strand as in case of tblastn,  hsp
  #belong to separate strand of query gets grouped into the same hit,  however
  #for gff3 format they should be splitted in separate hit groups.
    if ( lc $new_result->algorithm eq 'tblastn' ) {
        $self->split_hit_by_strand( $result, $new_result );
        $event->result_response($new_result);

        if ( $self->max_intron_length ) {

            #further splitting in case max intron length is given
            my $existing_result = $event->result_response;
            my $new_result2     = $self->clone_result($existing_result);
            $self->split_hit_by_intron_length( $existing_result, $new_result2,
                $self->max_intron_length );
            $self->_result_object($new_result2) if !$self->has_result_object;
            $event->result_response($new_result2);
        }

    }
    else {
        $new_result->add_hit($_) for $result->hits;
        $self->_result_object($new_result) if !$self->has_result_object;
        $event->result_response($new_result);
    }
}

sub split_hit_by_strand {
    my ( $self, $old_result, $new_result ) = @_;

HIT:
    while ( my $hit = $old_result->next_hit ) {
        my $hname
            = $self->hit_id_parser
            ? $self->get_parser( $self->hit_id_parser )->( $hit->name )
            : $hit->name;
        my $hacc = $hit->accession ? $hit->accession : $hname;

        my $plus_hit = Bio::Search::Hit::GenericHit->new(
            -name      => $hname . '-match-plus' . $self->global_hit_counter,
            -accession => $hacc,
            -algorithm => $hit->algorithm,
        );
        my $minus_hit = Bio::Search::Hit::GenericHit->new(
            -name      => $hname . '-match-minus' . $self->global_hit_counter,
            -accession => $hacc,
            -algorithm => $hit->algorithm,
        );

        for my $hsp ( $hit->hsps ) {
            if ( $hsp->strand('hit') == -1 ) {
                $hsp->hit->display_name( $minus_hit->name );
                $minus_hit->add_hsp($hsp);
            }
            else {
                $hsp->hit->display_name( $plus_hit->name );
                $plus_hit->add_hsp($hsp);
            }
        }
        $new_result->add_hit($plus_hit)  if $plus_hit->num_hsps  =~ /^\d+$/;
        $new_result->add_hit($minus_hit) if $minus_hit->num_hsps =~ /^\d+$/;

        $self->inc_global_hit_count;
    }
}

sub split_hit_by_intron_length {
    my ( $self, $old_result, $new_result, $intron_length ) = @_;
    my $coderef = sub {
        my ( $hsp_current, $hsp_next, $length ) = @_;
        my $distance = $hsp_next->start('hit') - $hsp_current->end('hit');
        return 1 if $distance > $length;
    };
    $self->_split_hit( $old_result, $new_result, $coderef, $intron_length );
}

sub split_overlapping_hit {
    my ( $self, $old_result, $new_result ) = @_;
    my $coderef = sub {
        my ( $current_hsp, $next_hsp ) = @_;
        if (    ( $current_hsp->end('hit') >= $next_hsp->start('hit') )
            and ( $current_hsp->end('hit') <= $next_hsp->end('hit') ) )
        {
            return 1;
        }
    };
    $self->_split_hit( $old_result, $new_result, $coderef );
}

sub _split_hit {
    my ( $self, $old_result, $new_result, $coderef, $param ) = @_;
HIT:
    while ( my $old_hit = $old_result->next_hit ) {
        my @hsps
            = sort { $a->start('hit') <=> $b->start('hit') } $old_hit->hsps;
        if ( @hsps == 1 ) {
            $new_result->add_hit($old_hit);
            next HIT;
        }

# array of hsp array
# [ ['hsp', 'hsp',  'hsp' ...],  ['hsp', 'hsp' ....], ['hsp',  'hsp',  'hsp' ...]]
        my $hsp_stack;

        # the index in the hsp stack where the next hsp should go
        my $index = 0;

     # the index of the hsp that is already been pushed into the new hsp stack
        my $pointer = {};
        for my $i ( 0 .. $#hsps - 1 ) {
            if ( not exists $pointer->{$i} ) {
                push @{ $hsp_stack->[$index] }, $hsps[$i];
                $pointer->{$i} = 1;
            }

            # coderef decides if the hsp stays in the current position
            my $return = $coderef->( $hsps[$i], $hsps[ $i + 1 ], $param );
            $index++ if $return;
            push @{ $hsp_stack->[$index] }, $hsps[ $i + 1 ];
            $pointer->{ $i + 1 } = 1;
        }

        if ( @$hsp_stack == 1 ) {
            $new_result->add_hit($old_hit);
        }
        else {
            for my $i ( 0 .. $#$hsp_stack ) {
                my $new_hit
                    = $self->clone_hit( $old_hit, $self->inc_hit_count );
                for my $new_hsp ( @{ $hsp_stack->[$i] } ) {
                    $new_hsp->hit->display_name( $new_hit->name );
                    $new_hit->add_hsp($new_hsp);
                }
                $new_result->add_hit($new_hit);
            }
            $self->reset_hit_count;
        }
    }
}

sub filter_hit {
    my ( $self, $event, $hit ) = @_;
    my @hsps = sort { $a->start('hit') <=> $b->start('hit') } $hit->hsps;
    return if @hsps == 1;

    my $index          = 0;
    my $merged_index   = {};
    my $new_hsps_index = {};
    my $end            = $#hsps;
OUTER:
    for my $i ( 0 .. $end - 1 ) {
        next OUTER if exists $merged_index->{$i};
    INNER:
        for my $y ( $i + 1 .. $end ) {
            if ( $hsps[$i]->end('hit') >= $hsps[$y]->end('hit') ) {
                $merged_index->{$y} = 1;
            }
        }
        $new_hsps_index->{$i} = 1;
    }

    # the last element needs to be checked
    $new_hsps_index->{$end} = 1 if not exists $merged_index->{$end};

    if ( scalar keys %$new_hsps_index ) {
        my $new_hit = $self->clone_hit($hit);
        $new_hit->add_hsp( $hsps[$_] ) for keys %$new_hsps_index;
        $event->hit_response($new_hit);
    }
}

sub write_result {
    my ( $self, $event, $result ) = @_;
    $self->_result_object($result);
}

sub write_hit {
    my ( $self, $event, $hit ) = @_;
    my $output = $self->output_handler;
    my $result = $self->_result_object;

    $output->print(
        gff3_format_feature(
            {   start  => $hit->start('hit'),
                end    => $hit->end('hit'),
                seq_id => $hit->accession,
                strand => $hit->strand('hit') == 1 ? '+' : '-',
                source => $self->source,
                type   => $self->primary_tag,
                score      => sprintf( "%.3g", $hit->significance ),
                attributes => {
                    ID   => [ $hit->name ],
                    Name => [ $result->query_name ],
                    Note => [ $result->query_description ]

                }
            }
        )
    );
}

sub write_hsp {
    my ( $self, $event, $hsp ) = @_;
    my $output = $self->output_handler;
    my $hit    = $hsp->hit;
    my $result = $self->_result_object;

    my @str = $hsp->cigar_string =~ /\d{1,3}[A-Z]?/g;
    my $target = sprintf "%s %d %d", $result->query_name, $hsp->start,
        $hsp->end;
    if ( lc $result->algorithm ne 'tblastn' ) {
        $target .= ' ' . $hsp->strand;
    }

    $output->print(
        gff3_format_feature(
            {   seq_id => $hit->seq_id,
                type   => 'match_part',
                source => $self->source,
                start  => $hsp->start('subject'),
                end    => $hsp->end('subject'),
                strand => $hsp->strand('hit') == 1 ? '+' : '-',
                score      => sprintf( "%.3g", $hsp->significance ),
                attributes => {
                    Gap    => [ join( ' ', @str ) ],
                    Parent => [ $hit->display_name ],
                    Target => [$target],
                }
            }
        )
    );
}

sub normalize_result_names {
    my ( $self, $result, $new_result ) = @_;
    my ( $qname, $qacc );
    if ( $self->format eq 'blastxml' ) {
        $qname
            = $self->query_id_parser
            ? $self->get_parser( $self->query_id_parser )
            ->( $result->query_description )
            : $result->query_description;
        $qacc = $qname;
    }
    else {
        my $qname
            = $self->query_id_parser
            ? $self->get_parser( $self->query_id_parser )
            ->( $result->query_name )
            : $result->query_name;
        $qacc
            = $result->query_accession
            ? $result->query_accession
            : $qname;
    }
    my $qdesc
        = $self->desc_parser
        ? $self->get_desc_parser( $self->desc_parser )
        ->( $result->query_description )
        : $result->query_description;

    $new_result->query_name($qname);
    $new_result->query_accession($qacc);
    $new_result->query_description($qdesc);
}

sub clone_minimal_result_fields {
    my ( $self, $result, $new_result ) = @_;
    $new_result->$_( $result->$_ ) for qw/query_length database_name
        algorithm/;
    $new_result->add_statistic( $_, $result->{statistics}->{$_} )
        for keys %{ $result->{statistics} };
}

sub clone_all_results_fields {
    my ( $self, $result, $new_result ) = @_;
    $self->clone_minimal_result_fields( $result, $new_result );
    $new_result->$_( $result->$_ )
        for qw/query_name query_accession query_description/;
}

sub clone_result {
    my ( $self, $old ) = @_;
    my $new = Bio::Search::Result::GenericResult->new;
    $self->clone_all_results_fields( $old, $new );
    return $new;
}

sub clone_hit {
    my ( $self, $old_hit, $counter ) = @_;
    my $name = $old_hit->name;
    $name .= sprintf( "%01d", $counter ) if $counter;
    my $new_hit = Bio::Search::Hit::GenericHit->new(
        -name      => $name,
        -accession => $old_hit->accession,
        -algorithm => $old_hit->algorithm,
    );
    return $new_hit;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Transform::Command::blast2gbrowsegff3 - Convert blast output to gff3 file to display in genome browser





