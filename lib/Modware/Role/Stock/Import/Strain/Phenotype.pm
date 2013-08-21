
package Modware::Role::Stock::Import::Strain::Phenotype;

use strict;

use Carp;
use Moose::Role;
use namespace::autoclean;

has '_environment' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_env_row => 'set',
        get_env_row => 'get',
        has_env_row => 'defined'
    }
);

has '_phenotype' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_phenotype => 'set',
        get_phenotype => 'get',
        has_phenotype => 'defined'
    }
);

sub find_or_create_environment {
    my ( $self, $env_term ) = @_;
    if ( $self->has_env_row($env_term) ) {
        return $self->get_env_row($env_term)->environment_id;
    }
    my $cvterm_env = $self->find_cvterm( $env_term, "Dicty Environment" );
    if ( !$cvterm_env ) {
        $self->logger->warn("Dicty environment ontology not loaded!");
        croak "Dicty environment ontology not loaded";
    }
    my $env_rs = $self->schema->resultset('Genetic::Environment')
        ->find_or_create( { uniquename => $env_term } );
    $env_rs->find_or_create_related( 'environment_cvterms',
        { cvterm_id => $cvterm_env } );

    $self->set_env_row( $env_term, $env_rs );
    return $self->get_env_row($env_term)->environment_id;
}

sub find_or_create_phenotype {
    my ( $self, $phenotype_term, $assay ) = @_;
    if ( $self->has_phenotype($phenotype_term) ) {
        return $self->get_phenotype($phenotype_term)->phenotype_id;
    }
    my $cvterm_phenotype
        = $self->find_cvterm( $phenotype_term, "Dicty Phenotypes" );
    if ( !$cvterm_phenotype ) {
		#$self->logger->logdie(
		#    "Couldn't find \"$phenotype_term\" in Dicty phenotype ontology");
        return;
    }
    my $cvterm_assay = $self->find_cvterm( $assay, "Dictyostelium Assay" )
        if $assay;
    if ( !$cvterm_assay and $assay ) {
        my $msg = "Couldn't find \"$assay\" in Dicty assay ontology";
        $self->logger->warn($msg);
    }
    my $phenotype_hash;
    $phenotype_hash->{uniquename}    = $phenotype_term;
    $phenotype_hash->{observable_id} = $cvterm_phenotype;
    $phenotype_hash->{assay_id}      = $cvterm_assay if $cvterm_assay;
    my $phenotype_rs
        = $self->schema->resultset('Phenotype::Phenotype')
        ->find_or_create($phenotype_hash);
    if ($phenotype_rs) {
        $self->set_phenotype( $phenotype_term, $phenotype_rs );
        return $self->get_phenotype($phenotype_term)->phenotype_id;
    }
}

1;

__END__

=head1 NAME
=head1 VERSION
=head1 SYNOPSIS
=head1 DESCRIPTION
=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT 
=cut
