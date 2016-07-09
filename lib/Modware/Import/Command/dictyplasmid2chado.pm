package Modware::Import::Command::dictyplasmid2chado;

use strict;

use File::Spec::Functions qw/catfile/;
use Moose;
use namespace::autoclean;

use Modware::Import::Utils;
use Modware::Import::Stock::PlasmidImporter;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Import::DataStash';

has prune => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
    documentation => 'Deletes all existing plasmid records before loading'
);

has data => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub {
        [qw/publications props inventory images genes sequence/];
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
    documentation =>
        'Mock publications, pub data is not populated. Default 0. Should be used only for testing code'
);

has image_url => (
    is  => 'rw',
    isa => 'Str',
    default =>
        'https://raw.githubusercontent.com/dictyBase/migration-data/master/plasmid/images/',
    documentation => 'Base URL for plasmid map images. Default github-url'
);

sub execute {
    my ($self) = @_;

    my $guard = $self->schema->txn_scope_guard;

    my $utils = Modware::Import::Utils->new();
    $utils->schema( $self->schema );
    $utils->logger( $self->logger );

    my $importer = Modware::Import::Stock::PlasmidImporter->new();
    $importer->logger( $self->logger );
    $importer->schema( $self->schema );
    $importer->utils($utils);

    if ($self->prune) {
        $importer->prune_plasmid;
    }
    my $prefix = 'plasmid_';
    my $input_file = catfile( $self->data_dir, $prefix . 'plasmid.tsv' );
    my $existing_stock = $importer->import_stock($input_file);
    foreach my $data ( @{ $self->data } ) {
        if ( $data eq 'images' ) {
            $importer->import_images( $self->image_url, $existing_stock );
            next;
        }
        if ( $data eq 'sequence' ) {
            if ( $self->seq_data_dir ) {
                $importer->import_plasmid_sequence( $self->seq_data_dir, $existing_stock );
            }
            else {
                $self->logger->warn("seq_data_folder not set");
            }
            next;
        }

        my $input_file = catfile( $self->data_dir, $prefix . $data . '.tsv' );
        my $import_data = 'import_' . $data;
        $importer->$import_data($input_file, $existing_stock);
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
