
use strict;

package Modware::Role::Stock::Plasmid;

use Bio::DB::GenBank;
use Bio::SeqIO;
use File::Path qw(make_path);
use Moose::Role;
use namespace::autoclean;
with 'Modware::Role::Stock::Commons';

has '_plasmid_invent_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_plasmid_invent_row => 'set',
        get_plasmid_invent_row => 'get',
        has_plasmid_invent     => 'defined'
    }
);

sub find_plasmid_inventory {
    my ( $self, $plasmid_id ) = @_;
    if ( $self->has_plasmid_invent($plasmid_id) ) {
        return $self->get_plasmid_invent_row($plasmid_id);
    }
    my $plasmid_invent_rs
        = $self->legacy_schema->resultset('PlasmidInventory')->search(
        { plasmid_id => $plasmid_id },
        {   select => [qw/me.location me.color me.stored_as me.storage_date/],
            cache  => 1
        }
        );
    if ( $plasmid_invent_rs->count > 0 ) {
        $self->set_plasmid_invent_row( $plasmid_id, $plasmid_invent_rs );
        return $self->get_plasmid_invent_row($plasmid_id);
    }
}

sub export_seq {
    my ( $self, $gb_dbp_hash ) = @_;
    $self->_get_genbank($gb_dbp_hash);
    $self->_export_existing_seq();
}

=head2 _get_ganbank
	my @ids = qw(1621261 89318838 68536103 20807972 730439);
	$command->_get_ganbank(@ids);

Writes files in GenBank format for each DBP_ID in the C<output_dir> folder
=cut

sub _get_genbank {
    my ( $self, $gb_dbp_hash ) = @_;

    my $seq_dir = Path::Class::Dir->new( $self->output_dir, 'sequence' );
    if ( !-d $seq_dir ) {
        make_path( $seq_dir->stringify );
    }

    my $gb  = Bio::DB::GenBank->new();
    my @ids = keys %$gb_dbp_hash;

    my $seqio = $gb->get_Stream_by_acc("@ids");
    while ( my $seq = $seqio->next_seq ) {
        my $outfile
            = $seq_dir->file(
            $gb_dbp_hash->{ $seq->accession_number } . ".genbank" )
            ->stringify;
        my $seqout = Bio::SeqIO->new(
            -file   => ">$outfile",
            -format => "genbank"
        );
        $seqout->write_seq($seq);
    }
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Plasmid - 

=head1 DESCRIPTION

A Moose Role for all the plasmid specific export tasks

=cut
