
use strict;

package Modware::Role::Stock::Export::Plasmid;

use Bio::DB::GenBank;
use Bio::SeqIO;
use File::Path qw(make_path);

# use IO::String;
use Moose::Role;
use namespace::autoclean;
with 'Modware::Role::Stock::Export::Commons';

has '_plasmid_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_plasmid_row => 'set',
        get_plasmid_row => 'get',
        has_plasmid     => 'defined'
    }
);

sub find_plasmid {
    my ( $self, $plasmid_name ) = @_;
    if ( $self->has_plasmid($plasmid_name) ) {
        return $self->get_plasmid_row($plasmid_name)->first->id;
    }
    my $plasmid_rs = $self->legacy_schema->resultset('Plasmid')->search(
        { name => $plasmid_name },
        {   select => [qw/me.id me.name/],
            cache  => 1
        }
    );
    if ( $plasmid_rs->count > 0 ) {
        $self->set_plasmid_row( $plasmid_name, $plasmid_rs );
        return $self->get_plasmid_row($plasmid_name)->first->id;
    }
}

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

    # my $response = $factory->get_Response();
    #if ( $response->is_success ) {
    #my $str     = IO::String->new( $response->decoded_content );
    #my $gb_seqs = Bio::SeqIO->new(
    #-fh     => $str,
    #-format => 'genbank'
    #);
    #while ( my $seq = $gb_seqs->next_seq ) {
    #print $seq->accession . "\n";
    #}
    # }
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Plasmid - 

=head1 DESCRIPTION

A Moose Role for all the plasmid specific export tasks

=cut
