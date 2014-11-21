package Modware::EventHandler::FeatureWriter::GFF3::Canonical::Dicty;

# Other modules:
use namespace::autoclean;
use Moose;
use Bio::GFF3::LowLevel qw/gff3_format_feature/;
extends 'Modware::EventHandler::FeatureWriter::GFF3::Canonical';

has '_gene_cache' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub { {} },
    handles => {
        has_gene_in_cache => 'exists',
        add_gene_in_cache => 'set'
    }
);

# Module implementation
#
sub write_gene {
    # my ( $self, $event, $seq_id, $dbrow, $synonyms ) = @_;
    # my $hash = $self->_dbrow2gff3hash( $dbrow, $event, $seq_id );
    # $hash->{attributes}->{Alias} = $synonyms if $synonyms;
    # $self->output->print( gff3_format_feature($hash) );
	return;
}

sub write_transcript {
    my ( $self, $event, $seq_id, $parent_dbrow, $dbrow, $synonyms ) = @_;
    my $output  = $self->output;
    my $gene_id = $self->_chado_feature_id($parent_dbrow);
    my $term;

    #check cache
    if ( $event->has_cvrow_id( $dbrow->type_id ) ) {
        $term = $event->get_cvrow_by_id( $dbrow->type_id )->name;
    }
    else {    #if not fills it up
        $term = $dbrow->type->name;
        $event->set_cvrow_by_id( $dbrow->type_id, $dbrow->type );
    }

    if ( $term eq 'pseudogene' ) {

        # dicty pseudogene gene model have to be SO complaint
        # it writes gene and transcript feature
        if ( !$self->has_gene_in_cache($gene_id) ) {
            my $pseudogene_hash
                = $self->pseudorow2gff3hash( $parent_dbrow, $seq_id, '',
                'pseudogene' );
            $output->print( gff3_format_feature($pseudogene_hash) );
            $self->add_gene_in_cache( $gene_id, 1 );
        }
        my $trans_hash = $self->pseudorow2gff3hash( $dbrow, $seq_id, $gene_id,
            'pseudogenic_transcript' );
        $output->print( gff3_format_feature($trans_hash) );
    }
    else {

        if ( !$self->has_gene_in_cache($gene_id) ) {
            my $gene_hash = $self->_dbrow2gff3hash( $parent_dbrow, $event, $seq_id );
			$gene_hash->{attributes}->{Alias} = $synonyms if $synonyms;
            $output->print( gff3_format_feature($gene_hash) );
            $self->add_gene_in_cache( $gene_id, 1 );
        }

        #transcript
        my $trans_hash = $self->_dbrow2gff3hash( $dbrow, $event, $seq_id, $gene_id );
        $output->print( gff3_format_feature($trans_hash) );
    }
}

sub write_exon {
    my ( $self, $event, $seq_id, $parent_dbrow, $dbrow ) = @_;
    my $output   = $self->output;
    my $trans_id = $self->_chado_feature_id($parent_dbrow);
    my $hash;
    if ( $event->get_cvrow_by_id( $parent_dbrow->type_id )->name eq 'pseudogene' ) {
        $hash = $self->pseudorow2gff3hash( $dbrow, $seq_id, $trans_id,
            'pseudogenic_exon' );
    }
    else {
        $hash = $self->_dbrow2gff3hash( $dbrow, $event, $seq_id, $trans_id );
    }
    $output->print( gff3_format_feature($hash) );
}

sub pseudorow2gff3hash {
    my ( $self, $dbrow, $seq_id, $parent_id, $type ) = @_;
    my $hashref;
    $hashref->{type}   = $type;
    $hashref->{seq_id} = $seq_id;
    $hashref->{score}  = undef;
    $hashref->{phase}  = undef;

    my $floc_row = $dbrow->featureloc_features->first;
    $hashref->{start} = $floc_row->fmin + 1;
    $hashref->{end}   = $floc_row->fmax;
    if ( my $strand = $floc_row->strand ) {
        $hashref->{strand} = $strand == -1 ? '-' : '+';
    }
    else {
        $hashref->{strand} = undef;
    }

    # source
    my $dbxref_rs
        = $dbrow->search_related( 'feature_dbxrefs', {} )->search_related(
        'dbxref',
        { 'db.name' => 'GFF_source' },
        { join      => 'db' }
        );
    if ( my $row = $dbxref_rs->first ) {
        $hashref->{source} = $row->accession;
    }
    else {
        $hashref->{source} = undef;
    }

    ## -- attributes
    $hashref->{attributes}->{ID} = [ $self->_chado_feature_id($dbrow) ];
    if ( my $name = $dbrow->name ) {
        $hashref->{attributes}->{Name} = [$name];
    }
    $hashref->{attributes}->{Parent} = [$parent_id] if $parent_id;
    my $dbxrefs;
    for my $xref_row ( grep { $_->db->name ne 'GFF_source' }
        $dbrow->secondary_dbxrefs )
    {
        my $dbname = $xref_row->db->name;
        $dbname =~ s/^DB:// if $dbname =~ /^DB:/;
        push @$dbxrefs, $dbname . ':' . $xref_row->accession;
    }
    $hashref->{attributes}->{Dbxref} = $dbxrefs if $dbxrefs;
    return $hashref;
}


sub write_polypeptide {
    my ( $self, $event, $seq_id, $parent_dbrow, $dbrow ) = @_;
    my $trans_id = $self->_chado_feature_id($parent_dbrow);
    my $hash = $self->_dbrow2gff3hash( $dbrow, $event, $seq_id );
    $hash->{attributes}->{Derives_from} = $trans_id;
    if ( not defined $hash->{start} ) {
            my $floc_row = $parent_dbrow->featureloc_features->first;
            $hash->{start}  = $floc_row->fmin + 1;
            $hash->{end}    = $floc_row->fmax;
            $hash->{strand} = $floc_row->strand == -1 ? '-' : '+';
    }
    # Removes the dot P from polypeptide ids
    my $poly_id = $hash->{attributes}->{ID}->[0];
    $poly_id =~ s/\.P$//;
    $hash->{attributes}->{ID} = [$poly_id];
    $self->output->print( gff3_format_feature($hash) );
}

sub write_synonym {
    return;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

<MODULE NAME> - [One line description of module's purpose here]


