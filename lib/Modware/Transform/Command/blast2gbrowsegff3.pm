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
    $parser->process;
}

#extract query accession, name and description from result object
# and split hits in case of tblastn

sub filter_result {
    my ( $self, $event, $result ) = @_;
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

    # construct a fresh result object
    my $new_result = Bio::Search::Result::GenericResult->new;
    $new_result->query_name($qname);
    $new_result->query_accession($qacc);
    $new_result->query_description($qdesc);
    $new_result->$_( $result->$_ ) for qw/query_length database_name
        algorithm/;
    $new_result->add_statistic( $_, $result->{statistics}->{$_} )
        for keys %{ $result->{statistics} };

#additional grouping of hsp's by the hit strand as in case of tblastn hsp
#belonging to separate strand of query gets grouped into the same hit,  however
#for gff3 format they should be splitted in separate hit groups.
    if ( lc $new_result->algorithm eq 'tblastn' ) {
        $self->split_hit_by_strand( $result, $new_result );
    }
    else {
        $new_result->add_hit($_) for $result->hits;
    }
    $self->_result_object($new_result) if !$self->has_result_object;
    $event->result_response($new_result);
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
            -name      => $hname . '-plus-strand',
            -accession => $hacc,
            -algorithm => $hit->algorithm,
        );
        my $minus_hit = Bio::Search::Hit::GenericHit->new(
            -name      => $hname . '-minus-strand',
            -accession => $hacc,
            -algorithm => $hit->algorithm,
        );

        for my $hsp ( $hit->hsps ) {
            if ( $hsp->strand('hit') == -1 ) {
            	$hsp->hit->display_name($minus_hit->name);
                $minus_hit->add_hsp($hsp);
            }
            else {
            	$hsp->hit->display_name($plus_hit->name);
                $plus_hit->add_hsp($hsp);
            }
        }
        $new_result->add_hit($plus_hit)  if $plus_hit->num_hsps  =~ /^\d+$/;
        $new_result->add_hit($minus_hit) if $minus_hit->num_hsps =~ /^\d+$/;
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
    if (lc $result->algorithm ne 'tblastn') {
    	$target .= ' '.$hsp->strand;
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

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Transform::Command::blast2gbrowsegff3 - Convert blast output to gff3 file to display in genome browser





