package Modware::Transform::Command::blast2chadogff3;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::SearchIO;
use Bio::Tools::GFF;
use Bio::SeqFeature::Generic;
extends qw/Modware::Transform::Command/;

has 'format' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'blast',
    lazy    => 1,
    documentation =>
        'Type of blast output,  either blast(text) or blastxml. For blastxml format the query name is parsed from query description'
);

has 'group' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 1,
    documentation => 'Generate a GFF3 line to group the HSP(s)'
);
has '+input' => ( documentation => 'blast result file' );
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

has 'target' => (
    is        => 'rw',
    isa       => 'Bool',
    default   => 1,
    predicate => 'add_target',
    documentation =>
        'whether to alwasy add the Target tag or not,  default is true. This also implies adding of Gap attribute'
);

has 'cutoff' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'an evalue cutoff',
    predicate     => 'has_cutoff'
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
    my $parser = Bio::SearchIO->new(
        -format => $self->format,
        -file   => $self->input
    );
    my $out = Bio::Tools::GFF->new(
        -file        => ">" . $self->output,
        -gff_version => 3
    );

RESULT:
    while ( my $result = $parser->next_result ) {
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

        $self->_result_object($result) if !$self->has_result_object;
    HIT:
        while ( my $hit = $result->next_hit ) {
            next HIT
                if $self->has_cutoff
                    and ( $hit->significance > $self->cutoff );

            my $hname
                = $self->hit_id_parser
                ? $self->get_parser( $self->hit_id_parser )->( $hit->name )
                : $hit->name;
            my $hacc = $hit->accession ? $hit->accession : $hname;

#additional grouping of hsp's by the hit strand as in case of tblastn hsp
#belonging to separate strand of query could be grouped into the same hit,  however
#they denotes separate matches and should be separated.
            my $hsp_group;
            while ( my $hsp = $hit->next_hsp ) {
                my $strand = $hsp->strand('hit') == 1 ? 'plus' : 'minus';
                push @{ $hsp_group->{$strand} }, $hsp;
            }

            # sort by hit start
            push @{ $hsp_group->{ 'strand' . $_ } },
                sort { $b->start('hit') <=> $a->start('hit') }
                @{ $hsp_group{$_} }
                for qw/plus minus/;

            for my $strand (qw/strandplus strandminus/) {
                if ( $self->group ) {
                    $out->write_feature(
                        Bio::SeqFeature::Generic->new(
                            -start =>
                                $hsp_group->{$strand}->[0]->start('hit'),
                            -end => $hsp_group->{$strand}->[-1]->end('hit'),
                            -seq_id      => $hname,
                            -source_tag  => $self->source,
                            -primary_tag => $self->primary_tag,
                            -score => sprintf( "%.3g", $hit->significance ),
                            -tag   => {
                                'ID'   => $qname,
                                'Note' => $qdesc,
                                'Name' => $qacc
                            }
                        )
                    );
                }

                for my $hsp ( @{ $hsp_group->{$strand} } ) {
                    my $feature = Bio::SeqFeature::Generic->new();
                    $feature->seq_id($hname);
                    $feature->primary_tag('match_part');
                    $feature->start( $hsp->start('subject') );
                    $feature->end( $hsp->end('subject') );
                    $feature->strand( $hsp->strand('hit') );
                    $feature->source_tag( $self->source );

                    if ( $self->group ) {
                        $feature->add_tag_value( 'Parent', $qname );
                    }
                    else {
                        $feature->score(
                            sprintf( "%.3g", $hsp->significance ) );
                    }

                    if ( $self->add_target ) {
                        $feature->add_tag_value( 'Target', $qname );
                        $feature->add_tag_value( 'Target', $hsp->start );
                        $feature->add_tag_value( 'Target', $hsp->end );
                        $feature->add_tag_value( 'Target', $hsp->strand );

                        my @str = $hsp->cigar_string =~ /\d{1,2}[A-Z]?/g;
                        $feature->add_tag_value( 'Gap', join( ' ', @str ) );
                    }

                    $out->write_feature($feature);
                }
            }
        }
    }
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Transform::Command::blast2chadogff3 - Convert blast output to gff3 file for loading in chado database





