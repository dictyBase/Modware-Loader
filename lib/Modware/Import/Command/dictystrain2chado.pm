package Modware::Import::Command::dictystrain2chado;

use strict;

use File::Spec::Functions qw/catfile/;
use Moose;
use namespace::autoclean;

use Modware::Import::Utils;
use Modware::Import::Stock::StrainImporter;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';

has 'prune' => ( is => 'rw', isa => 'Bool', default => 0 );

has data => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub {
        [   qw/characteristics publications inventory genotype phenotype props parent plasmid/
        ];
    },
    documentation =>
        'Data to be imported. Default all (characteristics, publications, inventory, genotype, phenotype, props, parent, plasmid)'
);

has dsc_phenotypes => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'File with corrected stockcenter phenotypes'
);

has strain_plasmid => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'File with strain-plasmids mapped to real plasmids'
);

has mock_pubs => (
    is            => 'rw',
    isa           => 'Bool',
    default       => 0,
    documentation => 'Boolean to create mock publications. Default 0'
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

    my $importer = Modware::Import::Stock::StrainImporter->new();
    $importer->logger( $self->logger );
    $importer->schema( $self->schema );
    $importer->utils($utils);

    my $prefix = 'strain_';
    my $input_file = catfile( $self->data_dir, $prefix . 'strain.tsv' );
    $importer->import_stock($input_file);
    foreach my $data ( @{ $self->data } ) {
        my $input_file = catfile( $self->data_dir, $prefix . $data . '.tsv' );
        my $import_data = 'import_' . $data;
        if ( $data eq 'phenotype' ) {
            $importer->$import_data( $input_file, $self->dsc_phenotypes );
            next;
        }
        if ( $data eq 'plasmid' ) {
            $importer->$import_data( $input_file, $self->strain_plasmid );
            next;
        }
        $importer->$import_data($input_file);
    }

    $guard->commit;
    $self->schema->storage->disconnect;

}

1;

__END__

=head1 NAME

Modware::Import::Command::dictystrain2chado - Command to import strain data from dicty stock 

=head1 VERSION
=head1 SYNOPSIS
=head1 DESCRIPTION
=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT
=cut