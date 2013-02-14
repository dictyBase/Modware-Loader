
use strict;

package Modware::Load::Command::dictygaf2chado;

use Moose;
use Moose::Util qw/ensure_all_roles/;
use namespace::autoclean;

use Modware::Loader::GAF;
use Modware::Loader::GAF::Manager;
extends qw/Modware::Load::Chado/;

has '+input'         => ( documentation => 'GAF file' );
has '+input_handler' => ( traits        => [qw/NoGetopt/] );

has 'prune' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 1,
    lazy          => 1,
    documentation => 'Prune all existing annotations, default is ON'
);

has 'print_gaf' =>
    ( is => 'rw', isa => 'Bool', documentation => 'Print GAF' );

has 'limit' => (
    is            => 'rw',
    isa           => 'Int',
    documentation => 'Limit for number of annotations to be loaded'
);

has 'ncrna' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    trigger => sub {
        my ($self) = @_;
        $self->logger->info('Appending ncRNA annotations');
        $self->meta->make_mutable;
        ensure_all_roles( $self,
            'Modware::Role::Command::GOA::Dicty::AppendncRNA' );
        $self->meta->make_immutable;
    },
    documentation => 'Load ncRNA annotations, default is OFF'
);

has 'dupes' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
    lazy    => 1,
    trigger => sub {
        my ($self) = @_;
        $self->logger->info('Appending annotations for duplicate genes');
        $self->meta->make_mutable;
        ensure_all_roles( $self,
            'Modware::Role::Command::GOA::Dicty::AppendDuplicate' );
        $self->meta->make_immutable;
    },
    documentation => 'Load duplicate gene annotations, default is OFF'
);

sub execute {
    my ($self) = @_;

    my $manager = Modware::Loader::GAF::Manager->new;
    $manager->set_logger( $self->logger );
    $manager->set_schema( $self->schema );

    my $loader = Modware::Loader::GAF->new;
    $loader->set_manager($manager);

    if ( $self->input ) {
        $loader->set_input( $self->input );
    }
    $loader->set_limit( $self->limit );

    my $guard = $self->schema->storage->txn_scope_guard;
    if ( $self->prune ) {
        $manager->prune();
    }
    $loader->load_gaf();
    $guard->commit;
    $self->logger->info( 'Finished loading '
            . $self->schema->resultset('Sequence::FeatureCvterm')
            ->search( {}, {} )->count
            . ' annotations' );
}

1;
