package Modware::DataSource::Chado::Organism;
use namespace::autoclean;
use Moose;

sub exists_in_datastore {
    my ( $self, $schema ) = @_;
    die "datastore schema option is not passed\n" if !$schema;
    if ( !$self->has_genus and !$self->has_species ) {
        die "common_name option is not set\n" if !$self->common_name;
        my $rs = $schema->resultset('Organism::Organism')
            ->search( { common_name => $self->common_name } );
        return if $rs->count == 0;
        if ( $rs->count > 1 ) {
            die "multiple organism with ", $self->common_name, "\n";
        }
        return 1;
    }
    die "genus options is required"   if !$self->has_genus;
    die "species options is required" if !$self->has_species;
    my $row = $schema->resultset('Organism::Organism')
        ->find( { species => $self->species, genus => $self->genus } );
    return $row if $row;
}

with 'Modware::Role::WithOrganism';
__PACKAGE__->meta->make_immutable;
1;
