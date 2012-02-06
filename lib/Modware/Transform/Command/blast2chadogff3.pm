package Modware::Transform::Command::blast2chadogff3;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::SearchIO;
use Bio::Tools::GFF;
use Bio::SeqFeature::Generic;
extends qw/Modware::Transform::Command/;

has 'group' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 1,
    documentation => 'To group the HSP(s) to single feature,  default is on'
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

has 'hit_counter' => (
    is      => 'rw',
    isa     => 'Num',
    traits  => [qw/Counter NoGetopt/],
    default => 0,
    handles => { inc_hit => 'inc', }
);

has 'hit_id_parser' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'hit id parser for the header line,  default is to use none ncbi,regular parsers are available'
);

has 'query_id_parser' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'query id parser for the header line,  default is to use none. ncbi,regular parsers are available'
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
            'ncbi'    => sub { $self->ncbi_parser(@_) },
            'regular' => sub { $self->regular_parser(@_) }
        };
    },
    lazy => 1
);

sub ncbi_parser {
    my ( $self, $string ) = @_;
    return $string if $string !~ /\|/;
    return ( ( split /\|/, $string ) )[1];
}

sub regular_parser {
    my ( $self, $string ) = @_;
    return $string if $string !~ /\|/;
    return ( ( split /\|/, $string ) )[0];
}

sub ncbi_desc_parser {
    my ( $self, $string ) = @_;
    return $string if $string !~ /\|/;
    my @values = ( split /\|/, $string ) ;
    my $desc = $values[-1];
    $desc =~ s/^\s*//g;
    $desc =~ s/\s*$//g;
    return $desc;
}

sub execute {
    my ($self) = @_;
    my $parser
        = Bio::SearchIO->new( -format => 'blast', -file => $self->input );
    my $out = Bio::Tools::GFF->new(
        -file        => ">" . $self->output,
        -gff_version => 3
    );

RESULT:
    while ( my $result = $parser->next_result ) {

        my $qname
            = $self->query_id_parser
            ? $self->get_parser( $self->query_id_parser )
            ->( $result->query_name )
            : $result->query_name;
        my $qacc
            = $result->query_accession ? $result->query_accession : $qname;

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

            if ( $self->group ) {
                $out->write_feature(
                    Bio::SeqFeature::Generic->new(
                        -start       => $hit->start('hit'),
                        -end         => $hit->end('hit'),
                        -seq_id      => $hname,
                        -source_tag  => $self->source,
                        -primary_tag => $self->primary_tag,
                        -score       => $hit->significance,
                        -tag => { 'ID' => $qname, 'Description' => $qdesc }
                    )
                );
            }

            while ( my $hsp = $hit->next_hsp ) {
                my $feature = Bio::SeqFeature::Generic->new();
                $feature->seq_id($hname);
                $feature->primary_tag('match_part');
                $feature->score( $hsp->significance );
                $feature->start( $hsp->start('subject') );
                $feature->end( $hsp->end('subject') );
                $feature->strand( $hsp->strand('hit') );
                $feature->source_tag( $self->source );

                if ( $self->group ) {
                    $feature->add_tag_value( 'Parent', $qname );
                }

                if ( $self->add_target ) {
                    $feature->add_tag_value( 'Target', $qname );
                    $feature->add_tag_value( 'Target', $hsp->start );
                    $feature->add_tag_value( 'Target', $hsp->end );
                    $feature->add_tag_value( 'Target', $hsp->strand );

                    my @str = unpack "(A2)*", $hsp->cigar_string;
                    $feature->add_tag_value( 'Gap', join( ' ', @str ) );
                }

                $out->write_feature($feature);
            }
        }
    }
}
__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Transform::Command::blast2chadogff3 - Convert blast output to gff3 file for loading in chado database





