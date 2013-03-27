package Modware::Collection::FeatureStack;
use namespace::autoclean;
use Moose;

has 'gene' => (
    is        => 'rw',
    isa       => 'Bio::SeqFeature::Generic',
    predicate => 'has_gene',
    clearer   => 'clear_gene'
);

has '_transcript' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    default => sub { [] },
    lazy    => 1,
    handles => {
        add_transcript         => 'push',
        num_of_transcripts     => 'count',
        delete_all_transcripts => 'clear',
        get_transcript         => 'get',
    }
);

has $_
    . '_row' => (
    is      => 'rw',
    isa     => 'DBIx::Class::Row',
    clearer => 'clear_' . $_ . '_row'
    ) for qw/src gene transcript/;

sub is_coding {
    my ($self) = @_;
    if ( $self->num_of_transcripts ) {
        my $t = $self->get_transcript(1);
        return 1 if $t->primary_tag eq 'mRNA';
    }
}

has 'polypeptide' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array/],
    default => sub { [] },
    lazy    => 1,
    handles => {
        add_polypeptide         => 'push',
        num_of_polypeptide      => 'count',
        has_polypeptide         => 'count',
        delete_all_polypeptides => 'clear',
        get_polypeptide         => 'get'
    }
);

has 'feature_position' => (
    is      => 'rw',
    isa     => 'Int',
    default => 0,
    lazy    => 1
);

sub delete_all_features {
    my ($self) = @_;
    $self->clear_gene;
    $self->delete_all_transcripts;
    $self->delete_all_polypeptides;

    #$self->clear_src_row;
    $self->clear_gene_row;
    $self->clear_transcript_row;
    $self->feature_position(0);
}

__PACKAGE__->meta->make_immutable;

1;

## -- Ideally this package should get populated from LSRN[http://lsrn.org] registry
