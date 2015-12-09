
package Modware::Role::Stock::Export::Strain;

use strict;

use FindBin qw($Bin);
use IO::File;
use Moose::Role;
use namespace::autoclean;
with 'Modware::Role::Stock::Export::Commons';

=head1 find_dbs_id

=cut 

sub find_strain {
    my ( $self, $strain_name ) = @_;

    my $strain = $self->legacy_schema->storage->dbh->selectall_arrayref(
        qq{
	SELECT DISTINCT dbxref_id, obtained_on
	FROM stock_center
	WHERE strain_name = '$strain_name'
	ORDER BY obtained_on ASC
	}
    );
    return @{$strain};
}

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

=head2 find_strain_inventory (Str $dbs_id)

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
                qw/me.location me.color me.no_of_vials me.obtained_as me.stored_as me.storage_date me.storage_comments me.other_comments_and_feedback/
            ],
            cache => 1
        }
        );
    if ( $strain_invent_rs->count > 0 ) {
        $self->set_strain_invent_row( $dbs_id, $strain_invent_rs );
        return $self->get_strain_invent_row($dbs_id);
    }
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

# sub find_phenotypes_2 {
#     my ( $self, $dbs_id ) = @_;
#     my @phenotypes;
#     my $genotype_rs = $self->schema->resultset('Genetic::Genotype')->search(
#         { 'me.uniquename' => $dbs_id },
#         {   join =>
#                 [ { 'phenstatements' => { 'phenotype' => 'observable' } } ],
#             select => [qw/observable.name/],
#             as     => [qw/phenotype_name/]
#         }
#     );
#     while ( my $genotype = $genotype_rs->next ) {
#         my $phenotype = $genotype->get_column('phenotype_name');
#         push @phenotypes, $phenotype if $phenotype;
#     }
#     return @phenotypes;
# }

=head2 find_phenotypes
	my @phenotypes = $command->find_phenotypes('dbs_id');
	foreach my $phenotype (@phenotypes) {
		print $phenotype->[0] ."\n";
	}

	Return a arrayref for the phenotypes of the given DBS ID. 
	Pure SQL query is performed for speed.
=cut

sub find_phenotypes {
    my ( $self, $dbs_id ) = @_;
    my $phenotypes = $self->schema->storage->dbh->selectall_arrayref(
        qq{
	SELECT phen.name, env.name, assay.name, pub.uniquename, p.value
	FROM phenstatement pst

	LEFT JOIN genotype g on g.genotype_id = pst.genotype_id
	
	LEFT JOIN cvterm env on env.cvterm_id = pst.environment_id
	LEFT JOIN cv env_cv on env_cv.cv_id = env.cv_id
	
	LEFT JOIN phenotype p on p.phenotype_id = pst.phenotype_id
	LEFT JOIN cvterm phen on phen.cvterm_id = p.observable_id
	
	LEFT JOIN cvterm assay on assay.cvterm_id = p.assay_id
	LEFT JOIN cv assay_cv on assay_cv.cv_id = assay.cv_id
	
	LEFT JOIN pub on pub.pub_id = pst.pub_id
	WHERE g.uniquename = '$dbs_id'
	}
    );
    return @{$phenotypes};
}

has '_genotype' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_strain_genotype => 'set',
        get_strain_genotype => 'get',
        has_strain_genotype => 'defined'
    }
);

sub _find_strain_genotypes {
    my ( $self, $dbs_id ) = @_;
    my $genotypes = $self->schema->storage->dbh->selectall_arrayref(
        qq{
	SELECT uniquename, description
	FROM genotype
	WHERE description IS NOT NULL
	}
    );
    for my $genotype ( @{$genotypes} ) {
        $self->set_strain_genotype( $genotype->[0], $genotype->[1] );
    }
}

sub _get_genotype_for_V_strain {
    my ( $self, $dbs_id ) = @_;
    my $base_ax4_genotype = 'axeA1,axeB1,axeC1,<gene_name>-,[pBSR1],bsR';
    if ( $self->has_strain_gene_name($dbs_id) ) {
        my @gene = @{ $self->get_strain_gene_name($dbs_id) };
        $base_ax4_genotype =~ s/<gene_name>/$gene[0]/;
    }
    else {
        $base_ax4_genotype =~ s/<gene_name>-,//;
    }
    return $base_ax4_genotype;
}

has '_strain_genes' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        set_strain_gene_name => 'set',
        get_strain_gene_name => 'get',
        has_strain_gene_name => 'defined'
    }
);

sub _find_strain_genes {
    my ( $self, $dbs_id ) = @_;
    my $strain_genes = $self->schema->storage->dbh->selectall_arrayref(
        qq{
	SELECT g.uniquename, f.name, gene_id.accession
	FROM feature_genotype fg
	JOIN genotype g ON g.genotype_id = fg.genotype_id
	JOIN feature f ON f.feature_id = fg.feature_id
	JOIN dbxref gene_id ON gene_id.dbxref_id = f.dbxref_id
	}
    );
    for my $strain_gene ( @{$strain_genes} ) {
        if ( !$self->has_strain_gene_name( $strain_gene->[0] ) ) {
            $self->set_strain_gene_name( $strain_gene->[0], [] );
        }
        push @{$self->get_strain_gene_name( $strain_gene->[0] )},
            $strain_gene->[1];
    }
}

1;

__END__

=head1 NAME

Modware::Role::Stock::Strain - 

=head1 DESCRIPTION
=head1 VERSION
=head1 SYNOPSIS
=head1 AUTHOR
=head1 LICENSE AND COPYRIGHT
=cut
