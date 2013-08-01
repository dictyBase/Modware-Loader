
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

sub export_seq {
    my ( $self, @genbank_ids, @plasmid_ids ) = @_;

    # $self->_get_genbank(@genbank_ids);
    $self->_export_existing_seq();
}

=head2 _get_ganbank
	my @ids = qw(1621261 89318838 68536103 20807972 730439);
	$command->get_ganbank(@ids);

Writes a file named plasmid_genbank.gb in the C<output_dir> folder
=item Reference L<EUtilities Cookbook|http://www.bioperl.org/wiki/HOWTO:EUtilities_Cookbook>
=cut

sub _get_genbank {
    my ( $self, @genbank_ids ) = @_;
    my $factory = Bio::DB::EUtilities->new(
        -eutil   => 'efetch',
        -db      => 'protein',
        -rettype => 'gb',
        -email   => 'developer@email.net',
        -id      => \@genbank_ids
    );
    my $file = $self->output_dir . "/plasmid_genbank.gb";
    $factory->get_Response( -file => $file );
}

=head2 _export_existing_seq

Parses dirty sequences in either FastA or GenBank formats and writes to files by DBP_ID

=cut 

sub _export_existing_seq {
    my ($self) = @_;
    my @formats = qw(genbank fasta);
    foreach my $format (@formats) {
        my $d = Path::Class::Dir->new( 'share', 'plasmid', $format );
        while ( my $input = $d->next ) {

            # $format = 'genbank' if $format eq 'genbank2';
            if ( ref($input) ne 'Path::Class::Dir'
                and $input->basename ne '.DS_Store' )
            {
                my $dbp_id = sprintf( "DBP%07d", $input->basename );
                my $seqin = Bio::SeqIO->new(
                    -file   => $input,
                    -format => $format
                );
                my $outfile
                    = $self->output_dir
                    . "/sequence/"
                    . $dbp_id . "."
                    . $format;
                my $seqout = Bio::SeqIO->new(
                    -file   => ">$outfile",
                    -format => $format
                );
                while ( my $seq = $seqin->next_seq ) {
                    if ($seq) {
                        $seq->id( $dbp_id . "|" . $seq->id );
                        $seqout->write_seq($seq);
                    }
                }
            }
        }
    }
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Plasmid - 

=head1 DESCRIPTION

A Moose Role for all the plasmid specific export tasks

=cut
