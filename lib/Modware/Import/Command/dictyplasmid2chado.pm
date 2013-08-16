
package Modware::Import::Command::dictyplasmid2chado;

use strict;

use Data::Dumper;
use Moose;
use namespace::autoclean;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Import::Plasmid';

has 'prune' => ( is => 'rw', isa => 'Bool', default => 0 );

has data => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [qw/publications inventory props/] }
);

sub execute {
    my ($self) = @_;

    my $guard = $self->schema->txn_scope_guard;

    if ( $self->prune ) {
        $self->schema->storage->dbh_do(
            sub {
                my ( $storage, $dbh ) = @_;
                my $sth = $dbh->prepare(qq{DELETE FROM stock});
                $sth->execute;
                $sth = $dbh->prepare(qq{DELETE FROM stockprop});
                $sth->execute;
                $sth->finish();
            }
        );
    }

    my $type_id = $self->schema->resultset('Cv::Cvterm')
        ->search( { name => 'plasmid' }, {} )->first->cvterm_id;

    my $io = IO::File->new( $self->input, 'r' );
    my $hash;

    while ( my $line = $io->getline ) {
        my @cols = split( /\t/, $line );
        $hash->{uniquename} = $cols[0] if $cols[0] =~ /^DBP[0-9]{7}/;
        $hash->{name} = $cols[1];

        #$hash->{organism_id} = $self->find_or_create_organism( $cols[2] )
        #    if $cols[2];
        $hash->{description} = $self->trim( $cols[2] );
        $hash->{type_id}     = $type_id;

        my $stock_rs
            = $self->schema->resultset('Stock::Stock')->create($hash);

        if ( $self->has_publications( $hash->{uniquename} ) ) {
            foreach my $pmid (
                @{ $self->get_publications( $hash->{uniquename} ) } )
            {
                my $pub_id = $self->find_pub($pmid);
                if ($pub_id) {
                    $stock_rs->create_related( 'stock_pubs',
                        { pub_id => $pub_id } );
                }
                else {
                    $self->logger->warn(
                        "Reference does not exist for PMID:$pmid");
                }
            }
        }

        if ( $self->has_inventory( $hash->{uniquename} ) ) {
            my $rank = 0;
            foreach my $inventory (
                @{ $self->get_inventory( $hash->{uniquename} ) } )
            {
                foreach my $key ( keys $inventory ) {
                    my $type = $key;
                    $type =~ s/_/ /g if $type =~ /_/;

                    $stock_rs->create_related(
                        'stockprops',
                        {   type_id => $self->find_cvterm($type, 'plasmid_inventory'),
                            value   => $self->trim( $inventory->{$key} ),
                            rank    => $rank
                        }
                    ) if $inventory->{$key};
                }
                $rank = $rank + 1;
            }
        }
    }

    $guard->commit;
    $self->schema->storage->disconnect;

    return;
}

1;

__END__

=head1 NAME

Modware::Import::Command::dictyplasmid2chado - Command to import plasmid data from dicty stock 

=head1 VERSION
=head1 SYNOPSIS
=head1 DESCRIPTION
=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT
=cut
