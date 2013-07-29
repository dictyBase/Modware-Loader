
use strict;

package Modware::Role::Stock::Strain;

use FindBin qw($Bin);
use IO::File;
use Moose::Role;
use namespace::autoclean;
with 'Modware::Role::Stock::Commons';

has '_strain_invent_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_strain_invent_row => 'set',
        get_strain_invent_row => 'get',
        has_strain_invent     => 'defined'
    }
);

=item find_strain_inventory (Str $dbs_id)

=cut

sub find_strain_inventory {
    my ( $self, $dbs_id ) = @_;
    if ( $self->has_strain_invent($dbs_id) ) {
        return $self->get_strain_invent_row($dbs_id);
    }
    my $old_dbxref_id
        = $self->schema->resultset('General::Dbxref')
        ->search( { accession => $dbs_id },
        { select => [qw/dbxref_id accession/] } )->first->dbxref_id;
    my $strain_invent_rs
        = $self->legacy_schema->resultset('StockCenterInventory')->search(
        { 'strain.dbxref_id' => $old_dbxref_id },
        {   join   => 'strain',
            select => [
                qw/me.location me.color me.no_of_vials me.obtained_as me.stored_as me.storage_date/
            ],
            cache => 1
        }
        );
    if ( $strain_invent_rs->count > 0 ) {
        $self->set_strain_invent_row( $dbs_id, $strain_invent_rs );
        return $self->get_strain_invent_row($dbs_id);
    }
}

has '_strain_characteristics' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => { is_strain_characteristic => 'defined' },
    lazy    => 1,
    builder => '_load_list_characteristics'
);

sub _load_list_characteristics {
    my ($self) = @_;
    my $dir = Path::Class::Dir->new($Bin);
    my $fh
        = IO::File->new(
        $dir->parent->subdir('share')->file('strain_characteristics.txt'),
        'r' );
    my $char_hashref;
    while ( my $io = $fh->getline ) {
        $char_hashref->{ $self->trim($io) } = 1;
    }
    return $char_hashref;
}

has '_strain_genotype' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    handles => { is_strain_genotype => 'defined' },
    lazy    => 1,
    builder => '_load_list_genotype'
);

sub _load_list_genotype {
    my ($self) = @_;
    my $dir = Path::Class::Dir->new($Bin);
    my $fh
        = IO::File->new(
        $dir->parent->subdir('share')->file('strain_genotype.txt'), 'r' );
    my $char_hashref;
    while ( my $io = $fh->getline ) {
        $char_hashref->{ $self->trim($io) } = 1;
    }
    return $char_hashref;
}

has '_mutagenesis_method' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub {
        {   'AS'        => 'Antisense',
            'EX'        => 'Extrachromosomal',
            'HR'        => 'Homologous Recombination',
            'HS'        => 'Haploid Segregant',
            'KD'        => 'Knockdown',
            'MR'        => 'Meiotic Recombination',
            'NG'        => 'N-Methyl-N-Nitro-N-Nitrosoguanidine',
            'NQNO'      => '4-nitroquinolone-N-oxide',
            'REMI'      => 'Restriction Enzyme-Mediated Integration',
            'RI'        => 'Random Insertion',
            'UV'        => 'Ultraviolet Light',
            'gamma-ray' => 'Gamma-Ray Irradiation',
            'spont'     => 'Spontaneous',
        };
    },
    handles => {
        get_mutagenesis_method => 'get',
        has_mutagenesis_method => 'defined'
    }
);

has '_synonym_row' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_synonym_row => 'set',
        get_synonym_row => 'get',
        has_synonym     => 'defined'
    }
);

sub get_synonyms {
    my ( $self, $strain_id ) = @_;
    my @synonyms;
    my $syn_rs
        = $self->legacy_schema->resultset('StrainSynonym')
        ->search( { strain_id => $strain_id },
        { select => 'synonym_id', cache => 1 } );
    while ( my $syn = $syn_rs->next ) {
        if ( $self->has_synonym( $syn->synonym_id ) ) {
            push( @synonyms,
                $self->get_synonym_row( $syn->synonym_id )->name );
        }
        else {
            my $synonym_rs
                = $self->schema->resultset('Sequence::Synonym')->search(
                { synonym_id => $syn->synonym_id },
                { select     => 'name', cache => 1 }
                );
            if ( $synonym_rs->count > 0 ) {
                while ( my $synonym = $synonym_rs->next ) {
                    $self->set_synonym_row( $syn->synonym_id, $synonym );
                    push( @synonyms,
                        $self->get_synonym_row( $syn->synonym_id )->name );
                }
            }
        }
    }
    return @synonyms;
}

sub find_phenotypes {
    my ( $self, $dbs_id ) = @_;
    my @phenotypes;
    my $pst_rs = $self->schema->resultset('Genetic::Phenstatement')->search(
        { 'genotype.uniquename' => $dbs_id },
        {   join     => [ 'genotype', { 'phenotype' => 'observable' } ],
            prefetch => [ 'genotype', { 'phenotype' => 'observable' } ],
            cache    => 1,
        }
    );
    while ( my $pst = $pst_rs->next ) {
        my $phenotype = $pst->phenotype;
        push( @phenotypes, $phenotype->observable->name );
    }
    return @phenotypes;
}

1;
