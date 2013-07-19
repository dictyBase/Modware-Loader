
use strict;

package Modware::Role::Stock::Plasmid;

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

=item find_plasmid_inventory (Str $dbs_id)

=cut

sub find_plasmid_inventory {
    my ( $self, $plasmid_id ) = @_;
    if ( $self->has_plasmid_invent($plasmid_id) ) {
        return $self->get_plasmid_invent_row($plasmid_id);
    }
    my $plasmid_invent_rs
        = $self->legacy_schema->resultset('PlasmidInventory')->search(
        { plasmid_id => $plasmid_id },
        {   select => [
                qw/me.location me.color me.stored_as me.storage_date/
            ],
            cache => 1
        }
        );
    if ( $plasmid_invent_rs->count > 0 ) {
        $self->set_plasmid_invent_row( $plasmid_id, $plasmid_invent_rs );
        return $self->get_plasmid_invent_row($plasmid_id);
    }
}
1;
