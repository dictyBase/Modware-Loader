package Modware::Load::Command::oboclosure2chado;
use strict;
use feature qw/say/;
use namespace::autoclean;
use Moose;
use SQL::Library;
extends qw/Modware::Load::Chado/;

has '+input' => (
    documentation =>
        'Name of chado closure file. You need owltools(http://code.google.com/p/owltools) to generate the closure file',
    required => 1
);
has '+input_handler' => ( traits => [qw/NoGetopt/] );
has 'dry_run' => (
    is            => 'rw',
    isa           => 'Bool',
    lazy          => 1,
    default       => 0,
    documentation => 'Dry run do not save anything in database'
);

has 'pg_schema' => (
    is        => 'rw',
    isa       => 'Str',
    predicate => 'has_pg_schema',
    documentation =>
        'Name of postgresql schema where the ontology will be loaded, default is public, obviously ignored for other backend'
);

has 'sqllib' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return SQL::Library->new(
            {   lib => module_file( 'Modware::Loader::',
                    ucfirst( lc( $self->schema->storage->sqlt_type ) ) )
                    . '_transitive.lib'
            }
        );
    },
    documentation =>
        'Path to sql library in INI format, by default picked up from the shared lib folder. Mostly a developer option.'
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;


    if ( $self->dry_run ) {
        $logger->info("Nothing saved in database");
    }
    else {
        $guard->commit;
    }
    $loader->finish;
}
1;

__END__

=head1 NAME

Modware::Load::Command::oboclosure2chado - Populate cvtermpath in chado database
 
