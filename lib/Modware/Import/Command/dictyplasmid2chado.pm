package Modware::Import::Command::dictyplasmid2chado;

use strict;

use File::Spec::Functions qw/catfile/;
use Moose;
use namespace::autoclean;

use Modware::Import::Utils;
use Modware::Import::Stock::PlasmidImporter;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';

has 'prune' => ( is => 'rw', isa => 'Bool', default => 0 );

has data => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub {

        # [qw/publications props inventory images/];
        [qw/sequence/];
    },
    documentation =>
        'Data to be imported. Default all (publications, props, inventory, images, sequence)'
);

has seq_data_dir => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'Path to folder with plasmid sequence files in GenBank|FastA formats'
);

has mock_pubs => (
    is      => 'rw',
    isa     => 'Bool',
    default => 0,
);

sub execute {
    my ($self) = @_;

    my $guard = $self->schema->txn_scope_guard;

    my $utils = Modware::Import::Utils->new();
    $utils->schema( $self->schema );
    $utils->logger( $self->logger );

    if ( $self->prune ) {
        $utils->prune_stock();
    }
    if ( $self->mock_pubs ) {
        $utils->mock_publications();
    }

    my $importer = Modware::Import::Stock::PlasmidImporter->new();
    $importer->logger( $self->logger );
    $importer->schema( $self->schema );
    $importer->utils($utils);

    my $base_image_url
        = "https://raw.github.com/dictyBase/migration-data/master/plasmid/images/";

    my $prefix = 'plasmid_';
    my $input_file = catfile( $self->data_dir, $prefix . 'plasmid.tsv' );
    $importer->import_stock($input_file);
    foreach my $data ( @{ $self->data } ) {
        if ( $data eq 'images' ) {
            $importer->import_images($base_image_url);
            next;
        }
        if ( $data eq 'sequence' ) {
            if ( $self->seq_data_dir ) {
                $importer->import_plasmid_sequence( $self->seq_data_dir );
            }
            else {
                $self->logger->warn("seq_data_folder not set");
            }
            next;
        }

        my $input_file = catfile( $self->data_dir, $prefix . $data . '.tsv' );
        my $import_data = 'import_' . $data;
        $importer->$import_data($input_file);
    }

    $guard->commit;
    $self->schema->storage->disconnect;

}

1;

__END__

=head1 NAME

Modware::Import::Command::dictyplasmid2chado - Command to import plasmid data from dicty stock 

=head1 VERSION
=head1 SYNOPSIS
=head1 DESCRIPTION
=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT
=cut