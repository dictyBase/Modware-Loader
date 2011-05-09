package Modware::Update::Command::oboinchado;

# Other modules:
use namespace::autoclean;
use Moose;
use Try::Tiny;
use Carp;
use Modware::Factory::Chado::BCS;
use Bio::Chado::Schema;
extends qw/Modware::Update::Command/;
with 'Modware::Role::Command::WithLogger';

# Module implementation
#

has '+data_dir' => ( traits => [qw/NoGetopt/] );

sub execute {
    my $self   = shift;
    my $log    = $self->logger;
    my $schema = Bio::Chado::Schema->connect( $self->dsn, $self->user,
        $self->password, $self->attribute );

    Modware::Factory::Chado::BCS->new( engine => $schema->storage->sqlt_type )
        ->transform($schema);
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Update ontology in chado database

