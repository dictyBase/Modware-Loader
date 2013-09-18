
package Modware::Role::Stock::Import::Utils;

use autodie;
use strict;

use Moose::Role;
use namespace::autoclean;

sub prune_stock {
	my ($self) = @_;
    $self->schema->storage->dbh_do(
        sub {
            my ( $storage, $dbh ) = @_;
            my $sth;
            for my $table (
                qw/stock stockprop stock_cvterm stock_pub stock_genotype genotype phenotype environment stock_relationship/
                )
            {
                $sth = $dbh->prepare(qq{DELETE FROM $table});
                $sth->execute;
            }
            $sth->finish;
        }
    );
}

sub _mock_publications {
    my ($self) = @_;
    my $dicty_phen_pub;
    $dicty_phen_pub->{title} = "Dicty Stock Center Phenotyping 2003-2008";
    $dicty_phen_pub->{type_id}
        = $self->find_or_create_cvterm( "ontology", "pub type" );
    $dicty_phen_pub->{uniquename} = '11223344';
    $self->schema->resultset('Pub::Pub')->find_or_create($dicty_phen_pub);

    my $dicty_char_pub;
    $dicty_char_pub->{title} = "Dicty Strain Characteristics";
    $dicty_char_pub->{type_id}
        = $self->find_or_create_cvterm( "ontology", "pub type" );
    $dicty_char_pub->{uniquename} = '11223345';
    $self->schema->resultset('Pub::Pub')->find_or_create($dicty_char_pub);
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    $s =~ s/[\n\r]/ /;
    return $s;
}

sub is_ontology_loaded {
	my ($self, $ontology) = @_;
	return $self->schema->resultset('Cv::Cv')->search({name => $ontology});
}

1;

__END__