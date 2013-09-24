package Modware::Loader::Role::WithStaging;

use strict;
use Moose::Role;
use SQL::Library;
use File::ShareDir qw/module_dir/;
use File::Spec::Functions;
use Modware::Loader;



requires
    qw(schema create_tables drop_tables create_indexes bulk_load count_entries_in_staging logger);

has 'sqlmanager' => (
    is      => 'rw',
    isa     => 'SQL::Library',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        my $lib = SQL::Library->new(
            {   lib => catfile(
                    module_dir('Modware::Loader'),
                    lc( $self->schema->storage->sqlt_type )
                        . '_transitive.lib'
                )
            }
        );
        return $lib;
    }
);

has 'chunk_threshold' =>
    ( is => 'rw', isa => 'Int', lazy => 1, default => 5000 );

1;
