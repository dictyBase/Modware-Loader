package Modware::Plugin::Import::Organism::Amoebozoa;
use Moose::Role;

sub raw2db_structure {
    my ( $self, $str ) = @_;
    my ( $dbarray, $species_hash );
    for my $entry (@$str) {
        next if exists $species_hash->{ $entry->{species} };
        my $dbhash;
        $dbhash->{genus}       = $entry->{genus};
        $dbhash->{common_name} = undef;
        if ( defined $entry->{common_name} ) {
            $dbhash->{common_name} = $entry->{common_name};
        }
        if ( defined $entry->{strain} ) {
            my $species = sprintf "%s %s", $entry->{species},
                $entry->{strain};
            $dbhash->{species} = $species;
            $species_hash->{$species} = 1;
        }
        else {
            $dbhash->{species} = $entry->{species};
            $species_hash->{ $entry->{species} } = 1;
        }
        $dbhash->{abbreviation}
            = uc( substr( $dbhash->{genus}, 0, 1 ) ) . '.'
            . $dbhash->{species};
        push @$dbarray, $dbhash;
    }
    return $dbarray;
}

1;
