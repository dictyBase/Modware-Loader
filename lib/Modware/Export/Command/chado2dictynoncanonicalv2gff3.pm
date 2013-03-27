package Modware::Export::Command::chado2dictynoncanonicalv2gff3;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Modware::EventEmitter::Feature::Chado;
use Modware::EventHandler::FeatureReader::Chado::NonCanonical::Dicty;
use Modware::EventHandler::FeatureWriter::GFF3::NonCanonical::DictyV2;
extends qw/Modware::Export::Chado/;

# Module implementation
#

has '+species'  => ( traits  => [qw/NoGetopt/] );
has '+genus'    => ( traits  => [qw/NoGetopt/] );
has '+organism' => ( default => 'dicty', traits => [qw/NoGetopt/] );
has '+input'    => ( traits  => [qw/NoGetopt/] );
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

sub execute {
    my ($self) = @_;

    my $read_handler
        = Modware::EventHandler::FeatureReader::Chado::NonCanonical::Dicty
        ->new(
        reference_type => 'chromosome',
        common_name    => 'dicty'
        );
    my $write_handler
        = Modware::EventHandler::FeatureWriter::GFF3::NonCanonical::DictyV2
        ->new( output => $self->output_handler, );

    my $source = $self->schema->source('Sequence::Feature');
    $source->remove_column('is_obsolete');
    $source->add_column(
        'is_deleted' => {
            data_type     => 'boolean',
            is_nullable   => 0,
            default_value => 'false'
        }
    );

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

Modware::Export::Command::chado2dictynoncanonicalv2gff3 -  Export GFF3 with repredicted gene models of Dictyostelium discoideum

