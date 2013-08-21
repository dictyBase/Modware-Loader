
use strict;

package Modware::Role::Stock::Export::Plasmid;

use Bio::DB::GenBank;
use Bio::SeqIO;
use File::Path qw(make_path);

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

=head2 _export_existing_seq

Parses dirty sequences in either FastA or GenBank formats and writes to files by DBP_ID

=cut 

sub _export_existing_seq {
    my ($self) = @_;
    my @formats = qw(genbank fasta);

    my $seq_dir = Path::Class::Dir->new( $self->output_dir, 'sequence' );
    if ( !-d $seq_dir ) {
        make_path( $seq_dir->stringify );
    }
    foreach my $format (@formats) {
        my $d = Path::Class::Dir->new( 'share', 'plasmid', $format );
        while ( my $input = $d->next ) {

         # TODO - Fix 8 sequences that are almost GenBank (in genbank2 folder)
         # $format = 'genbank' if $format eq 'genbank2';
            if ( ref($input) ne 'Path::Class::Dir' ) {
                my $dbp_id = sprintf( "DBP%07d", $input->basename );
                my $seqin = Bio::SeqIO->new(
                    -file   => $input,
                    -format => $format
                );
                my $outfile
                    = $seq_dir->file( $dbp_id . "." . $format )->stringify;
                my $seqout = Bio::SeqIO->new(
                    -file   => ">$outfile",
                    -format => $format
                );
                while ( my $seq = $seqin->next_seq ) {
                    if ($seq) {
                        $seq->id($dbp_id);
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
