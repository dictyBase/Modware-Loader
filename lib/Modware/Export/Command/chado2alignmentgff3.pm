package Modware::Export::Command::chado2alignmentgff3;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Modware::EventEmitter::Feature::Chado;
use Modware::EventHandler::FeatureReader::Chado::Overlapping;
use Modware::EventHandler::FeatureWriter::GFF3::Canonical;
extends qw/Modware::Export::Chado/;

# Module implementation
#

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

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;

    my $read_handler
        = Modware::EventHandler::FeatureReader::Chado::Overlapping->new(
        reference_type => $self->reference_type,
        feature_type   => $self->feature_type
        );
    $read_handler->species( $self->species )      if $self->species;
    $read_handler->genus( $self->genus )          if $self->genus;
    $read_handler->common_name( $self->organism ) if $self->organism;

    my $write_handler
        = Modware::EventHandler::FeatureWriter::GFF3::Alignment->new(
        output => $self->output_handler );
    my $event = Modware::EventEmitter::Feature::Chado->new(
        resource => $self->schema );

    $event->on( 'read_reference' => sub { $read_handler->read_reference(@_) }
    );
    $event->on( 'read_organism' => sub { $read_handler->read_organism(@_) } );
    $event->on( 'write_header'  => sub { $write_handler->write_header(@_) } );
    for my $ftype (qw/feature subfeature/) {
        my $read  = 'read_' . $ftype;
        my $write = 'write_' . $ftype;
        $event->on( $read  => sub { $read_handler->$read(@_) } );
        $event->on( $write => sub { $read_handler->$write(@_) } );
    }
    $event->process;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::chado2alignmentgff3 -  Export alignment from chado database in
GFF3 format

