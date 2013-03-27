package Modware::Export::Command::chado2alignmentgff3;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Modware::EventEmitter::Feature::Chado;
use Modware::EventHandler::FeatureReader::Chado::Overlapping;
use Class::Load qw/load_class/;
extends qw/Modware::Export::Chado/;

# Module implementation
#

has '+input' => ( traits => [qw/NoGetopt/] );
has 'write_sequence_region' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'write sequence region header in GFF3 output,  default if off'
);

has 'feature_name' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Output feature name instead of sequence id in the seq_id field,  default is off.'
);

has 'reference_type' => (
    isa         => 'Str',
    is          => 'rw',
    traits      => [qw/Getopt/],
    cmd_aliases => 'rt',
    documentation =>
        'The SO type of reference feature,  default is supercontig',
    default => 'supercontig',
    lazy    => 1
);

has 'feature_type' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'SO type of alignment features to be exported'
);

has 'match_type' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return $self->feature_type . '_match';
    },
    documentation =>
        'SO type of alignment feature that will be exported in GFF3, *_match* is appended to the feature_type by default.'
);

has 'force_name' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    documentation =>
        'Adds the value of GFF3 *ID* attribute to *Name* attribute(if absent),  off by default'
);

has 'add_description' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    documentation =>
        'If present,  add the GFF3 *Note* attribute. It looks for a feature property with *description* cvterm. Off by default'
);

has 'property' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [] },
    lazy    => 1,
    traits  => [qw/Array/],
    handles => { num_of_properties => 'count', all_properties => 'elements' },
    documentation =>
        'List of additional cvterms which will be used to extract additional feature properties'
);

has 'fix_dicty_coordinates' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    documentation =>
        'Correct the EST match coordinate specifically for dictyBase alignment'
);

sub execute {
    my ($self) = @_;

    my $read_handler
        = Modware::EventHandler::FeatureReader::Chado::Overlapping->new(
        reference_type => $self->reference_type,
        feature_type   => $self->feature_type
        );
    $read_handler->species( $self->species )      if $self->species;
    $read_handler->genus( $self->genus )          if $self->genus;
    $read_handler->common_name( $self->organism ) if $self->organism;

    my $write_handler;
    if ( $self->feature_type eq 'EST' and $self->fix_dicty_coordinates ) {
        load_class(
            'Modware::EventHandler::FeatureWriter::GFF3::Alignment::Dicty');
        $write_handler
            = Modware::EventHandler::FeatureWriter::GFF3::Alignment::Dicty
            ->new(
            output     => $self->output_handler,
            match_type => $self->match_type
            );
    }
    else {
        load_class('Modware::EventHandler::FeatureWriter::GFF3::Alignment');
        $write_handler
            = Modware::EventHandler::FeatureWriter::GFF3::Alignment->new(
            output     => $self->output_handler,
            match_type => $self->match_type
            );
    }
    $write_handler->force_name( $self->force_name );
    $write_handler->force_description( $self->add_description );
    if ( $self->num_of_properties ) {
        $write_handler->add_property($_) for $self->all_properties;
    }

    my $event = Modware::EventEmitter::Feature::Chado->new(
        resource => $self->schema );

    $event->on( 'read_reference' => sub { $read_handler->read_reference(@_) }
    );
    $event->on( 'read_seq_id' => sub { $read_handler->read_seq_id(@_) } );
    $event->on(
        'read_seq_id' => sub { $read_handler->read_seq_id_by_name(@_) } )
        if $self->feature_name;
    $event->on( 'write_sequence_region' =>
            sub { $write_handler->write_sequence_region(@_) } )
        if $self->write_sequence_region;

    $event->on( 'read_organism' => sub { $read_handler->read_organism(@_) } );
    $event->on( 'write_header'  => sub { $write_handler->write_header(@_) } );
    for my $ftype (qw/feature subfeature/) {
        my $read  = 'read_' . $ftype;
        my $write = 'write_' . $ftype;
        $event->on( $read  => sub { $read_handler->$read(@_) } );
        $event->on( $write => sub { $write_handler->$write(@_) } );
    }
    $event->process( $self->log_level );
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::chado2alignmentgff3 -  Export alignment from chado database in GFF3 format

