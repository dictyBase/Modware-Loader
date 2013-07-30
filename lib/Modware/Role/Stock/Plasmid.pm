
use strict;

package Modware::Role::Stock::Plasmid;

use Bio::DB::EUtilities;
use Bio::SeqIO;
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

=head2 get_ganbank
	my @ids = qw(1621261 89318838 68536103 20807972 730439);
	$command->get_ganbank(@ids);

	Writes a file named plasmid_genbank.gb in the C<output_dir> folder
=cut

sub get_genbank {
    my ( $self, @genbank_ids ) = @_;
    my $factory = Bio::DB::EUtilities->new(
        -eutil   => 'efetch',
        -db      => 'protein',
        -rettype => 'gb',
        -email   => 'mymail@foo.bar',
        -id      => \@genbank_ids
    );
    my $file = $self->output_dir . "/plasmid_genbank.gb";
    $factory->get_Response( -file => $file );
}

1;
