package Modware::Export::Command::colleague2gene;

use strict;
use Moose;
use namespace::autoclean;
use Text::CSV;
extends qw/Modware::Export::Command/;
with 'Modware::Role::Command::WithDBI';
with 'Modware::Role::Command::WithIO';

has '+input' => ( traits => [qw/NoGetopt/] );

has 'statement' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => q{
        SELECT email.email, feature.uniquename FROM cgm_ddb.email 
        JOIN cgm_ddb.coll_email ON 
          email.email_no = coll_email.email_no
          JOIN cgm_ddb.coll_locus ON 
            coll_email.colleague_no = coll_locus.colleague_no
            JOIN feature ON
              coll_locus.locus_no = feature.feature_id
              ORDER BY email.email
    }
);

has '_colleague_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        add_colleague            => 'set',
        has_colleague            => 'exists',
        get_colleague            => 'get',
        get_colleagues_and_genes => 'kv',
        prune_colleagues         => 'clear'
    }
);

sub execute {
    my ($self) = @_;
    my $dbh    = $self->dbh;
    my $sth    = $dbh->prepare( $self->statement );
    $sth->execute;
    my $output = $self->output_handler;
    my $csv = Text::CSV->new( { auto_diag => 1, binary => 1 } );
    $csv->print( $output, [ "Colleague email", "Gene IDs" ] );
    $output->print("\n");
    while ( my $hashref = $sth->fetchrow_hashref('NAME_lc') ) {
        if ( $self->has_colleague( $hashref->{email} ) ) {
            my $colleague_value = $self->get_colleague( $hashref->{email} );
            push @$colleague_value, $hashref->{uniquename};
        }
        else {
            for my $pair ( $self->get_colleagues_and_genes ) {
                $csv->print($output, [$pair->[0], @{$pair->[1]}]);
                $output->print("\n");
            }
            $self->prune_colleagues;
            $self->add_colleague( $hashref->{email},
                [ $hashref->{uniquename} ] );
        }
    }
}

1;

__END__

=head1 NAME

Modware::Export::Command::colleague2gene - Export a csv format of dictybase colleagues and their associated genes
