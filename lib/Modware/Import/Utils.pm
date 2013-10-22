
package Modware::Import::Utils;

use autodie;
use strict;

use Moose;
use namespace::autoclean;

# use String::Random;

has schema => ( is => 'rw', isa => 'DBIx::Class::Schema' );
has logger => ( is => 'rw', isa => 'Log::Log4perl::Logger' );

with 'Modware::Role::Stock::Import::DataStash';

sub prune_stock {
    my ($self) = @_;
    $self->schema->storage->dbh_do(
        sub {
            my ( $storage, $dbh ) = @_;
            my $sth;
            for my $table (
                qw/stockcollection stockcollection_stock feature stock stockprop stock_cvterm stock_pub stock_genotype genotype phenotype environment stock_relationship phenstatement phenotypeprop/
                )
            {
                $sth = $dbh->prepare(qq{DELETE FROM $table});
                $sth->execute;
            }
            $sth->finish;
        }
    );
    return;
}

sub mock_publications {
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
    return;
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    $s =~ s/[\n\r]/ /;
    return $s;
}

sub is_ontology_loaded {
    my ( $self, $ontology ) = @_;
    return $self->schema->resultset('Cv::Cv')
        ->search( { name => $ontology } );
}

sub is_stock_loaded {
    my ( $self, $stock ) = @_;
    return $self->schema->resultset('Stock::Stock')
        ->search( { 'type.name' => $stock }, { join => 'type' } )->count;
}

sub is_genotype_loaded {
    my ($self) = @_;
    return $self->schema->resultset('Genetic::Genotype')
        ->search( {}, { join => 'stock_genotypes' } )->count;
}

has '_uniquename' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_uniquename => 'set',
        has_uniquename => 'defined',
    }
);

# sub generate_uniquename {
#     my ( $self, $prefix ) = @_;
#     my $id_generator = String::Random->new();
#     my $uniquename   = $id_generator->randregex( $prefix . "[0-9]{7}" );
#     if ( !$self->has_uniquename($uniquename) ) {
#         $self->set_uniquename( $uniquename, 1 );
#         return $uniquename;
#     }
#     $self->generate_uniquename($prefix);
#     return;
# }

sub nextval {
    my ( $self, $tablename, $prefix ) = @_;
    my $seq = sprintf "%s_%s_%s_%s", $tablename, $tablename, 'id', 'seq';
    my $dbh = $self->schema->storage->dbh;
    my $nextval
        = $dbh->selectall_arrayref(qq{SELECT NEXTVAL('$seq')})->[0][0];
    my $new_id = sprintf "%s%07d", $prefix, $nextval;
    return $new_id;
}

1;

__END__