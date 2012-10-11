package Modware::Export::Command::chado2canonicalgff3;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Modware::EventEmitter::Feature::Chado::Canonical;
use Modware::EventHandler::FeatureReader::Chado::Canonical;
use Modware::EventHandler::FeatureWriter::GFF3::Canonical;
extends qw/Modware::Export::Chado/;

# Module implementation
#

has 'write_sequence' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
    documentation =>
        'To write the fasta sequence(s) of reference feature(s),  default is true'
);

has 'exclude_mitochondrial' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Exclude mitochondrial genome,  default is to include if it is present'
);

has 'only_mitochondrial' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Output only mitochondrial genome if it is present,  default is false'
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

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;

    my $handler
        = Modware::EventHandler::FeatureReader::Chado::Canonical->new(
        reference_type => $self->reference_type
        );
	$handler->species($self->species) if $self->species;
	$handler->genus($self->genus) if $self->genus;
	$handler->common_name($self->organism) if $self->organism;

    my $write_handler
        = Modware::EventHandler::FeatureWriter::GFF3::Canonical->new(
        output => $self->output_handler );

    my $event = Modware::EventEmitter::Feature::Chado::Canonical->new(
        resource => $self->schema );

    for my $name (qw/reference seq_id contig gene transcript exon/) {
        my $read_api  = 'read_' . $name;
        my $write_api = 'write_' . $name;
        $event->on( $read_api  => sub { $handler->$read_api(@_) } );
        $event->on( $write_api => sub { $write_handler->$write_api(@_) } );
    }
    $event->on( 'read_organism' => sub { $handler->read_organism(@_) } );
    $event->on( 'write_header'  => sub { $write_handler->write_header(@_) } );
    $event->on( 'write_sequence_region' =>
            sub { $write_handler->write_sequence_region(@_) } );
    $event->on( 'write_reference_sequence' =>
            sub { $write_handler->write_reference_sequence(@_) } );

    if ( $self->exclude_mitochondrial ) {
        $event->on( 'read_reference' =>
                sub { $handler->read_reference_without_mito(@_) } );
    }
    if ( $self->only_mitochondrial ) {
        $event->on(
            'read_reference' => sub {
                $handler->read_mito_reference(@_);
            }
        );
    }
    $event->process;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::chado2canonicalgff3 -  Export GFF3 of canonical gene models from chado database

