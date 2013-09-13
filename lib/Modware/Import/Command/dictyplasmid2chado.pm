
package Modware::Import::Command::dictyplasmid2chado;

use strict;

use DBD::Pg qw(:pg_types);
use File::Spec::Functions qw/catfile/;
use LWP::Simple qw/head/;
use Moose;
use namespace::autoclean;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Import::Plasmid';

has 'prune' => ( is => 'rw', isa => 'Bool', default => 0 );

has data => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [qw/publications inventory props/] },
    documentation =>
        'Data to be imported. Options available publications, inventory, props. Default ALL'
);

has 'plasmid_map' => (
    is            => 'rw',
    isa           => 'Bool',
    default       => undef,
    documentation => 'Should plasmid map jpeg urls be saved'
);

sub execute {
    my ($self) = @_;

    my $guard = $self->schema->txn_scope_guard;

    if ( $self->prune ) {
        $self->schema->storage->dbh_do(
            sub {
                my ( $storage, $dbh ) = @_;
                my $sth;
                for my $table (qw/stock stockprop stock_pub/) {
                    $sth = $dbh->prepare(qq{DELETE FROM $table});
                    $sth->execute;
                }
                $sth->finish;
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
        $self->set_stock_row( $hash->{uniquename}, $stock_rs );
    }

    for my $dbp_id ( $self->get_dbs_ids ) {
        my $stock_rs = $self->get_stock_row($dbp_id);

        # Plasmid publications
        if ( $self->has_publications($dbp_id) ) {
            foreach my $pmid ( @{ $self->get_publications($dbp_id) } ) {
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

        # Plasmid inventory
        if ( $self->has_inventory($dbp_id) ) {
            my $rank = 0;
            foreach my $inventory ( @{ $self->get_inventory($dbp_id) } ) {
                foreach my $key ( keys $inventory ) {
                    my $type = $key;
                    $type =~ s/_/ /g if $type =~ /_/;

                    $stock_rs->create_related(
                        'stockprops',
                        {   type_id => $self->find_cvterm(
                                $type, 'plasmid_inventory'
                            ),
                            value => $self->trim( $inventory->{$key} ),
                            rank  => $rank
                        }
                    ) if $inventory->{$key};
                }
                $rank = $rank + 1;
            }
        }

        # Plasmid properties (depositor, keyword, synonym)
        if ( $self->has_props($dbp_id) ) {
            my $rank;
            my $previous_type = '';
            my @props         = @{ $self->get_props($dbp_id) };
            foreach my $prop (@props) {
                my ( $key, $value ) = each %{$prop};
                $rank = 0 if $previous_type ne $key;
                my $props_type_id
                    = $self->find_cvterm( $key, "dicty_stockcenter" );
                $stock_rs->create_related(
                    'stockprops',
                    {   type_id => $props_type_id,
                        value   => $self->trim($value),
                        rank    => $rank
                    }
                );
                $rank          = $rank + 1;
                $previous_type = $key;
            }
        }

        if ( $self->plasmid_map ) {
            ( my $filename = $dbp_id ) =~ s/^DBP[0]+//;
            my $github_base_url
                = "https://raw.github.com/dictyBase/migration-data/master/plasmid/images/";
            my $image_url = $github_base_url . $filename . ".jpg";
            if ( head($image_url) ) {
                $stock_rs->create_related(
                    'stockprops',
                    {   type_id => $self->find_or_create_cvterm(
                            'plasmid map', 'dicty_stockcenter'
                        ),
                        value => $image_url
                    }
                );
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
