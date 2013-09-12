
package Modware::Import::Command::dictyplasmid2chado;

use strict;

use DBD::Pg qw(:pg_types);
use File::Spec::Functions qw/catfile/;
use Moose;
use namespace::autoclean;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Import::Plasmid';

has 'prune' => ( is => 'rw', isa => 'Bool', default => 0 );

has data => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub { [qw/publications inventory props images/] },
    documentation =>
        'Data to be imported. Options available publications, inventory, props. Default ALL'
);

has 'plasmid_map' => (
    is            => 'rw',
    isa           => 'Str',
    default       => undef,
    documentation => 'Folder path with plasmids map images'
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

        # Plasmid inventory
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
        if ( $self->has_props( $hash->{uniquename} ) ) {

            my $rank;
            my $previous_type = '';
            my @props         = @{ $self->get_props( $hash->{uniquename} ) };
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
            my $filepath = catfile( $self->plasmid_map, $filename . ".jpg" );
            my $filehandle = IO::File->new;
            if ( -e $filepath ) {

                # my $io = $filehandle->open($filepath);
                open( IMAGE, $filepath );
                binmode(IMAGE);
                my $buf;
                my $data;
                while ( read( IMAGE, $buf, 10000 ) ) { $data .= $buf; }
                close(IMAGE);

                if ($data) {
                    $self->schema->storage->dbh_do(
                        sub {
                            my ( $storage, $dbh ) = @_;
                            my $sth
                                = $dbh->prepare(
                                "INSERT INTO stockprop (stock_id, type_id, value) VALUES ( ?,?,? ) "
                                ) or die "PREPARE FAILED";

                            $sth->bind_param( 3, undef,
                                { pg_type => PG_BYTEA } );
                            $sth->execute(
                                $stock_rs->stock_id,
                                $self->find_or_create_cvterm(
                                    'plasmid map', 'dicty_stockcenter'
                                ),
                                $data
                            ) or die "EXECUTE FAILED";
                            $sth->finish;
                        }
                    );
                }

                $self->schema->storage->dbh_do(
                    sub {
                        my ( $storage, $dbh ) = @_;
                        my $sth = $dbh->prepare(
                            "SELECT sp.value
								FROM stockprop sp
								JOIN stock s ON s.stock_id = sp.stock_id
								JOIN cvterm typ ON typ.cvterm_id = sp.type_id
								WHERE typ.name = 'plasmid map'
								AND s.uniquename = ?"
                        );
                        $sth->execute($dbp_id);

                        my $content = $sth->fetchrow_array();
                        if ($content) {
                            my $new_file = "image_test/" . $dbp_id . ".jpg";
                            open( F, ">$new_file" );
                            binmode(F);
                            print F $content;
                            close(F);
                        }
                    }
                );

                # $stock_rs->create_related(
                #     'stockprops',
                #     {   type_id => $self->find_or_create_cvterm(
                #             'plasmid map', 'dicty_stockcenter'
                #         ),
                #         value => $data
                #     }
                # );
                print sprintf "%s\t%s\n", $dbp_id, $filepath;
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
