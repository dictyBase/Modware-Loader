
use strict;

package Modware::Role::Stock::Import::Commons;

use Moose::Role;
use namespace::autoclean;

has 'db' => ( is => 'rw', isa => 'Str', default => 'internal' );
has 'cv' => ( is => 'rw', isa => 'Str', default => 'dicty_stockcenter' );

before 'execute' => sub {
    my ($self) = @_;

    my @cvterms = (
        "strain",             "plasmid",
        "genotype",           "synonym",
        "mutagenesis method", "mutant type"
    );
    my $dictystock_rs = $self->schema->resultset('Cv::Cvterm')->search(
        {   'me.name' => { -in => [@cvterms] },
            'cv.name' => $self->cv
        },
        { join => 'cv' }
    );
    if ( $dictystock_rs->count == 0 ) {
        $self->logger->info(
            'Creating dicty_stockcenter namespace in cv & cvterm');
        my $cv_stock_rs
            = $self->schema->resultset('Cv::Cv')
            ->find_or_create( { name => $self->cv } );
        foreach my $stock (@cvterms) {
            $cv_stock_rs->create_related(
                'cvterms',
                {   name      => $stock,
                    dbxref_id => $self->find_or_create_dbxref($stock)
                },
            );
        }
    }
};

sub find_or_create_dbxref {
    my ( $self, $accession ) = @_;
    my $dbxref_rs
        = $self->schema->resultset('General::Dbxref')->find_or_create(
        {   accession => $accession,
            db_id     => $self->find_or_create_db()
        }
        );
    return $dbxref_rs->dbxref_id;
}

sub find_or_create_db {
    my ($self) = @_;
    my $db_rs = $self->schema->resultset('General::Db')
        ->find_or_create( { name => $self->db } );
    return $db_rs->db_id;
}

has '_organism_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_organism_row => 'set',
        get_organism_row => 'get',
        has_organism_row => 'defined'
    }
);

sub find_or_create_organism {
    my ( $self, $species ) = @_;
    my @organism = split( / /, $species );
    if ( $self->has_organism_row($species) ) {
        return $self->get_organism_row($species)->organism_id;
    }
    my $row
        = $self->schema->resultset('Organism::Organism')
        ->search( { species => $organism[1] },
        { select => [qw/organism_id species/] } );
    if ( $row->count > 0 ) {
        $self->set_organism_row( $species, $row->first );
        return $self->get_organism_row($species)->organism_id;
    }
    else {
        my $new_organism_row
            = $self->schema->resultset('Organism::Organism')->create(
            {   genus        => $organism[0],
                species      => $organism[1],
                common_name  => $organism[1],
                abbreviation => substr( $organism[0], 0, 1 ) . "."
                    . $organism[1]
            }
            );
        $self->set_organism_row( $species, $new_organism_row );
        return $self->get_organism_row($species)->organism_id;
    }
}

has '_pub_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_pub_row => 'set',
        get_pub_row => 'get',
        has_pub_row => 'defined'
    }
);

sub find_pub {
    my ( $self, $pmid ) = @_;
    if ( $self->has_pub_row($pmid) ) {
        return $self->get_pub_row($pmid)->pub_id;
    }
    my $row
        = $self->schema->resultset('Pub::Pub')
        ->search( { uniquename => $pmid },
        { select => [qw/pub_id uniquename/] } );
    if ( $row->count > 0 ) {
        $self->set_pub_row( $pmid, $row->first );
        return $self->get_pub_row($pmid)->pub_id;
    }
}

has '_cvterm_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_cvterm_row => 'set',
        get_cvterm_row => 'get',
        has_cvterm_row => 'defined'
    }
);

sub find_cvterm {
    my ( $self, $name, $cv_name ) = @_;

    # if ( $self->has_cvterm_row($name) ) {
    #     return $self->get_cvterm_row($name)->cvterm_id;
    # }
    my $row = $self->schema->resultset('Cv::Cvterm')->search(
        { 'me.name' => $name, 'cv.name' => $cv_name },
        { join      => 'cv',  select    => [qw/cvterm_id name/] }
    );
    if ( $row->count > 0 ) {

        # $self->set_cvterm_row( $name, $row->first );
        # return $self->get_cvterm_row($name)->cvterm_id;
        return $row->first->cvterm_id;
    }
}

sub find_or_create_cvterm {
    my ( $self, $cvterm, $cv ) = @_;
    my $cvterm_id = $self->find_cvterm( $cvterm, $cv );
    if ( !$cvterm_id ) {
        my $row = $self->schema->resultset('Cv::Cvterm')->find_or_create(
            {   name      => $cvterm,
                dbxref_id => $self->find_or_create_dbxref($cvterm),
                cv_id     => $self->find_cv($cv)
            }
        );
        $self->set_cvterm_row( $cvterm, $row );
        $cvterm_id = $row->cvterm_id;
    }
    return $cvterm_id;
}

sub find_cv {
    my ( $self, $cv ) = @_;
    my $row = $self->schema->resultset('Cv::Cv')
        ->search( { name => $cv }, { select => 'cv_id' } );
    my $cv_id;
    if ($row) {
        $cv_id = $row->first->cv_id;
    }
    return $cv_id;
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Import::Commons - 

=head1 DESCRIPTION

=cut
