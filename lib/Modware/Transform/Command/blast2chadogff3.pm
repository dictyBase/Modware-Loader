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
        return $self->_result_object->algorithm;
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

sub execute {
    my ($self) = @_;
    my $parser
        = Bio::SearchIO->new( -format => 'blast', -file => $self->input );
    my $out = Bio::Tools::GFF->new( -file => ">".$self->output,  -gff_version => 3 );


RESULT:
    while ( my $result = $parser->next_result ) {
        my $qname = $result->query_name;
        my $desc  = $result->query_description;
        $self->_result_object($result) if !$self->has_result_object;
    HIT:
        while ( my $hit = $result->next_hit ) {
            next HIT
                if $self->has_cutoff
                    and ( $hit->significance > $self->cutoff );

            my $name     = $hit->name;
            my $acc      = $qname . '-' . $name;
            my $gff_name = $name . $self->hit_counter;
            my @hsps;
            if ( $self->group ) {
                @hsps = sort {$a->start('hit') <=> $b->start('hit') }$hit->hsps;
                $out->write_feature(
                    Bio::SeqFeature::Generic->new(
                        -start       => $hsps[0]->start('hit'),
                        -end         => $hsps[-1]->end('hit'),
                        -seq_id      => $name,
                        -source_tag  => $self->source,
                        -primary_tag => $self->primary_tag,
                        -tag         => { 'ID' => $gff_name }
                    )
                );
                $self->inc_hit;
            }

            my $counter = 01;
            for my $hsp (@hsps )
                {
                    my $feature = Bio::SeqFeature::Generic->new;
                    $feature->seq_id($name);
                    $feature->primary_tag('match_part');
                    $feature->score( $hsp->evalue );
                    $feature->start( $hsp->start('hit') );
                    $feature->end( $hsp->end('hit') );
                    $feature->strand( $hit->strand );
                    $feature->source_tag( $self->source );
                    $feature->add_tag_value( 'ID',   $acc . $counter );
                    $feature->add_tag_value( 'Name', $desc );

                    if ( $self->group ) {
                        $feature->add_tag_value( 'Parent', $gff_name );
                    }

                    if ( $self->add_target ) {
                        $feature->add_tag_value( 'Target', $qname );
                        $feature->add_tag_value( 'Target', $hsp->start );
                        $feature->add_tag_value( 'Target', $hsp->end );
                        $feature->add_tag_value( 'Target', $hsp->strand );

                        my @str = unpack "(A2)*", $hsp->cigar_string;
                        $feature->add_tag_value( 'Gap', join( ' ', @str ) );
                        $counter++;
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





