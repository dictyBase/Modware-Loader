package Modware::Export::Command::chado2dictynoncanonicalgff3;

use strict;
use namespace::autoclean;
use Moose;
use Modware::EventEmitter::Feature::Chado::Canonical;
use Modware::EventHandler::FeatureReader::Chado::Canonical::Dicty;
use Modware::EventHandler::FeatureWriter::GFF3::NonCanonical::Dicty;

extends qw/Modware::Export::Chado/;

# Other modules:

# Module implementation
#

# this is specific for dicty,  no need to expose them in command line
has '+species'  => ( traits  => [qw/NoGetopt/] );
has '+genus'    => ( traits  => [qw/NoGetopt/] );
has '+organism' => ( default => 'dicty', traits => [qw/NoGetopt/] );
has '+input'    => ( traits  => [qw/NoGetopt/] );
has 'reference_id' => (
    is  => 'rw',
    isa => 'Str',
    'documentation' =>
        'reference feature name/ID/accession number. In this case,  only all of its associated features will be dumped'
);
has 'feature_name' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'Output feature name instead of sequence id in the seq_id field,  default is off.'
);
has 'write_sequence_region' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    documentation =>
        'write sequence region header in GFF3 output,  default if off'
);

has 'source' => (
	is => 'rw', 
	isa => 'Str', 
	lazy => 1, 
	default => 'Sequencing Center', 
	documentation => 'Name of database/piece of software/algorithm that generated the gene models. By default it is *Sequencing Center*.'
);

sub execute {
    my ($self) = @_;
    my $read_handler
        = Modware::EventHandler::FeatureReader::Chado::Canonical::Dicty->new(
        reference_type => 'chromosome',
        common_name    => 'dicty', 
        source => $self->source
        );

    my $write_handler
        = Modware::EventHandler::FeatureWriter::GFF3::NonCanonical::Dicty->new(
        output => $self->output_handler );

    my $source = $self->schema->source('Sequence::Feature');
    $source->remove_column('is_obsolete');
    $source->add_column(
        'is_deleted' => {
            data_type     => 'boolean',
            is_nullable   => 0,
            default_value => 'false'
        }
    );
    my $event = Modware::EventEmitter::Feature::Chado::Canonical->new(
        resource => $self->schema );

    for my $name (qw/reference seq_id gene exon/) {
        my $read_api = 'read_' . $name;
        $event->on( $read_api => sub { $read_handler->$read_api(@_) } );
    }
    $event->on('read_transcript' => sub {$read_handler->read_transcript_by_source(@_)});
    $event->on(
        'write_transcript' => sub { $write_handler->write_transcript(@_) } );
    $event->on( 'write_exon' => sub { $write_handler->write_exon(@_) } );

    if ( $self->reference_id ) {
        $read_handler->reference_id( $self->reference_id );
        $event->on( 'read_reference' =>
                sub { $read_handler->read_reference_by_id(@_) } );
    }

    $event->on( 'read_organism' => sub { $read_handler->read_organism(@_) } );
    $event->on( 'write_header'  => sub { $write_handler->write_header(@_) } );
    $event->on( 'write_sequence_region' =>
            sub { $write_handler->write_sequence_region(@_) } )
        if $self->write_sequence_region;

    if ( $self->feature_name ) {
        $event->on(
            'read_seq_id' => sub { $read_handler->read_seq_id_by_name(@_) } );
    }
    $event->process( $self->log_level );
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Export::Command::chado2dictynoncanonicalgff3 - Export GFF3 with sequencing center gene models of Dictyostelium discoideum


