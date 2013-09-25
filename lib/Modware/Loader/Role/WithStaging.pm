package Modware::Loader::Role::WithStaging;

use strict;
use Moose::Role;



requires
    qw(schema create_tables drop_tables create_indexes bulk_load count_entries_in_staging logger);

has 'sqlmanager' => (
    is      => 'rw',
    isa     => 'SQL::Library',
);

has 'chunk_threshold' =>
    ( is => 'rw', isa => 'Int', lazy => 1, default => 5000 );

1;
