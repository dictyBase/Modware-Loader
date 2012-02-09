package Modware::Transform::Command::blast2chadogff3;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::SearchIO;
use Bio::Tools::GFF;
use Bio::SeqFeature::Generic;
use Modware::Iterator::Array;
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
            my $top_group;
            if ( lc $self->_result_object->algorithm eq 'tblastn' ) {
                my $hsp_group;
                while ( my $hsp = $hit->next_hsp ) {
                    my $strand = $hsp->strand('hit') == 1 ? 'plus' : 'minus';
                    push @{ $hsp_group->{$strand} }, $hsp;
                }

                # now try to group non overlapping hsps(ignoring the frames)
                $top_group = $self->non_overlapping($hsp_group);

            }
            else {
                $top_group = Modware::Iterator::Array->new;
                my $inner_group = Modware::Iterator::Array->new;
                $inner_group->add($_) for $hit->hsps;
                $top_group->add($inner_group);
            }

            my $end = $top_group->member_count - 1;
        GROUP:
            for my $i ( 0 .. $end ) {
                my $gff_acc;
                my $inner = $top_group->get_by_index($i);
                if ( $self->group ) {
                    $gff_acc = $qname . '.match' . $i;

                    my $gend;
                    if ( $inner->member_count == 1 ) {
                        $gend = $inner->get_by_index(0)->end('hit');
                    }
                    else {
                        $gend = $inner->get_by_index(-1)->end('hit');
                    }

                    $out->write_feature(
                        Bio::SeqFeature::Generic->new(
                            -start  => $inner->get_by_index(0)->start('hit'),
                            -end    => $gend,
                            -seq_id => $hname,
                            -source_tag  => $self->source,
                            -primary_tag => $self->primary_tag,
                            -score => sprintf( "%.3g", $hit->significance ),
                            -tag   => {
                                'ID'   => $gff_acc,
                                'Note' => $qdesc,
                                'Name' => $qacc
                            }
                        )
                    );
                }

                for my $hsp ( $inner->members ) {
                    my $feature = Bio::SeqFeature::Generic->new();
                    $feature->seq_id($hname);
                    $feature->primary_tag('match_part');
                    $feature->start( $hsp->start('subject') );
                    $feature->end( $hsp->end('subject') );
                    $feature->strand( $hsp->strand('hit') );
                    $feature->source_tag( $self->source );

                    if ( $self->group ) {
                        $feature->add_tag_value( 'Parent', $gff_acc );
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

sub non_overlapping {
    my ( $self, $hsp_group ) = @_;

    my $super_container = Modware::Iterator::Array->new;

    for my $k ( keys %$hsp_group ) {
        my $hsp_array = $hsp_group->{$k};
        if ( @$hsp_array == 1 ) {
            my $c = Modware::Iterator::Array->new;
            $c->add( $hsp_array->[0] );
            $super_container->add($c);
        }

        elsif ( @$hsp_array == 2 ) {
            my $sorted = [ sort { $a->start('hit') <=> $b->start('hit') }
                    @$hsp_array ];
            if ( $sorted->[0]->end('hit') < $sorted->[1]->start('hit') ) {
                my $c = Modware::Iterator::Array->new;
                $c->add($_) for @$sorted;
                $super_container->add($c);
            }
            else {
                my $c = Modware::Iterator::Array->new;
                $c->add( $sorted->[0] );
                my $c2 = Modware::Iterator::Array->new;
                $c2->add( $sorted->[1] );
                $super_container->add($c);
                $super_container->add($c2);
            }
        }

        else {
            my $sorted = [ sort { $a->start('hit') <=> $b->start('hit') }
                    @$hsp_array ];
            my $end = $#$hsp_array - 1;
            my $non_overlap_idx;
        OUTER:
            for my $i ( 0 .. $end ) {
                next OUTER if defined $non_overlap_idx->{$i};
            INNER:
                for my $y ( $i + 1 .. $end + 1 ) {
                    next INNER if defined $non_overlap_idx->{$y};
                    if ( $sorted->[$i]->end('hit')
                        < $sorted->[$y]->start('hit') )
                    {    ## -- non overlapping
                        $non_overlap_idx->{$y} = 'overlap';
                        $non_overlap_idx->{$i} = 'overlap';
                    }
                }
            }

            my $container = Modware::Iterator::Array->new;
            $container->add( $sorted->[$_] ) for keys %$non_overlap_idx;
            if ( $container->has_member ) {
                $super_container->add($container);
            }

            for my $z ( 0 .. $#$sorted ) {
                if ( not defined $non_overlap_idx->{$z} ) {
                    my $c = Modware::Iterator::Array->new;
                    $c->add( $sorted->[$z] );
                    $super_container->add($c);
                }
            }
        }
    }
    return $super_container;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Transform::Command::blast2chadogff3 - Convert blast output to gff3 file for loading in chado database





