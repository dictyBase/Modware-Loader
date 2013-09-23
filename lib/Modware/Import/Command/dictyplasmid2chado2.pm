package Modware::Import::Command::dictyplasmid2chado2;

use strict;

use File::Spec::Functions qw/catfile/;
use Moose;
use namespace::autoclean;

use Modware::Import::Stock::PlasmidImporter;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Import::Utils';

has 'prune' => ( is => 'rw', isa => 'Bool', default => 0 );

has data => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub {
        [qw/publications props inventory images/];
    }
);

has mock_pubs => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

sub execute {
    my ($self) = @_;

    my $guard = $self->schema->txn_scope_guard;

    if ( $self->prune ) {
        $self->prune_stock();
    }
    if ( $self->mock_pubs ) {
        $self->mock_publications();
    }

    my $importer = Modware::Import::Stock::PlasmidImporter->new();
    $importer->logger( $self->logger );
    $importer->schema( $self->schema );

    my $base_image_url
        = "https://raw.github.com/dictyBase/migration-data/master/plasmid/images/";

    my $prefix = 'plasmid_';
    my $input_file = catfile( $self->data_dir, $prefix . 'plasmid.tsv' );
    $importer->import_stock($input_file);
    foreach my $data ( @{ $self->data } ) {
        if ( $data ne 'images' ) {
            my $input_file
                = catfile( $self->data_dir, $prefix . $data . '.tsv' );
            my $import_data = 'import_' . $data;
            $importer->$import_data($input_file);
        }
        else {
            $importer->import_images($base_image_url);
        }
    }

    $guard->commit;
    $self->schema->storage->disconnect;

}

1;

__END__

=head1 NAME

Modware::Import::Command::dictyplasmid2chado2 - Command to import plasmid data from dicty stock 

=head1 VERSION
=head1 SYNOPSIS
=head1 DESCRIPTION
=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT
=cut