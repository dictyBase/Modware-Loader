
use strict;

package Modware::Loader::GAF;

use Moose;
use namespace::autoclean;

has 'gaf' => (
    is  => 'rw',
    isa => 'IO::File'
);

has 'manager' => (
    is  => 'rw',
    isa => 'Modware::Loader::GAF::Manager',
	writer => 'set_manager'
);

sub set_input {
    my ( $self, $input ) = @_;
    my $io = IO::File->new( $input, 'r' );
    $self->gaf($io);
}

sub load_gaf {
    my ($self) = @_;
    if ( !$self->gaf ) {
        $self->logger->warn();
        exit;
    }
    else {
        while ( my $row = $self->gaf->getline ) {
            $self->manager->logger->info($row);
            my $annotation = $self->manager->parse();
            if ( !$annotation ) {
                next;
            }
        }
    }
}

sub get_rank {

}

sub upsert {

}

1;
