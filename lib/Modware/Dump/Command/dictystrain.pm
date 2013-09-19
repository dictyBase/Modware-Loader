
package Modware::Dump::Command::dictystrain;

use strict;

use Data::Dumper;
use Modware::Legacy::Schema;
use Moose;
use namespace::autoclean;

extends qw/Modware::Dump::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Export::Strain';
with 'Modware::Role::Stock::Export::Plasmid';

has data => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub {
        [   qw/strain inventory genotype phenotype publications genes characteristics props parent plasmid/
        ];
    },
    documentation =>
        'Option to dump all data (default) or (strain, inventory, genotype, phenotype, publications, genes, characteristics, props, parent, plasmid)'
);

sub execute {
    my ($self) = @_;

    my ( $io, $stats ) = $self->_create_files();

    my $strain_rs = $self->legacy_schema->resultset('StockCenter')
        ->search( {}, { cache => 1 } );
    $strain_rs->result_class('DBIx::Class::ResultClass::HashRefInflator');

    my $dscg = 1;

    while ( my $strain = $strain_rs->next ) {

        my $dbs_id = $self->find_dbxref_accession( $strain->{dbxref_id} );
        my $dscg_id = sprintf( "DSC_G%07d", $dscg );

        if ( exists $io->{strain} ) {
            my @row;
            push @row, $dbs_id;
            push @row, $self->trim( $strain->{strain_name} );
            if ( $strain->{species} ) {
                push @row, $strain->{species};
            }
            else {
                push @row, '';
            }

            if ( $strain->{strain_description} ) {
                my $strain_desc
                    = $self->trim( $strain->{strain_description} );
                push @row, $strain_desc;
            }
            else {
                push @row, '';
            }

            my $s = join( "\t", @row );
            $io->{strain}->write( $s . "\n" );
            $stats->{strain} = $stats->{strain} + 1;
        }

        if ( exists $io->{inventory} ) {
            my $strain_invent_rs = $self->find_strain_inventory($dbs_id);
            if ($strain_invent_rs) {
                $strain_invent_rs->result_class(
                    'DBIx::Class::ResultClass::HashRefInflator');
                while ( my $strain_invent = $strain_invent_rs->next ) {
                    my @row;
                    push @row, $dbs_id;
                    if ( $strain_invent->{location} ) {
                        push @row, $self->trim( $strain_invent->{location} );
                    }
                    else {
                        push @row, '';
                    }

                    my $color
                        = $self->trim( ucfirst( $strain_invent->{color} ) );
                    if ( length($color) > 1 ) {
                        push @row, $color;
                    }
                    else {
                        push @row, '';
                    }

                    if (    $strain_invent->{no_of_vials}
                        and $strain_invent->{no_of_vials} =~ /^\d+$/ )
                    {
                        push @row,
                            $self->trim( $strain_invent->{no_of_vials} );
                    }
                    else {
                        push @row, '';
                    }

                    if ( $strain_invent->{obtained_as} ) {
                        my $strain_obtained_as
                            = $self->trim( $strain_invent->{obtained_as} );
                        if ( length($strain_obtained_as) > 1 ) {
                            push @row, $strain_obtained_as;
                        }
                        else {
                            push @row, '';
                        }
                    }
                    else {
                        push @row, '';
                    }

                    my $strain_stored_as = $strain_invent->{stored_as};
                    if ( $strain_stored_as and length($strain_stored_as) > 1 )
                    {
                        $strain_stored_as =~ s/\?//g;
                        $strain_stored_as = $self->trim($strain_stored_as);
                        if ( length($strain_stored_as) > 1 ) {
                            push @row, $strain_stored_as;
                        }
                        else {
                            push @row, '';
                        }
                    }
                    else {
                        push @row, '';
                    }

                    if ( $strain_invent->{storage_date} ) {
                        push @row,
                            $self->trim( $strain_invent->{storage_date} );
                    }
                    else {
                        push @row, '';
                    }

                    my $private_comment = $strain_invent->{storage_comments};
                    if ($private_comment) {
                        $private_comment =~ s/[\n\r]/ /g;
                        push @row, $self->trim($private_comment);
                    }
                    else {
                        push @row, '';
                    }

                    my $public_comment
                        = $strain_invent->{other_comments_and_feedback};
                    if ($public_comment) {
                        $public_comment =~ s/[\n\r]/ /g;
                        push @row, $self->trim($public_comment);
                    }
                    else {
                        push @row, '';
                    }

                    my $s = join( "\t", @row );
                    $io->{inventory}->write( $s . "\n" );
                    $stats->{inventory} = $stats->{inventory} + 1;
                }
            }
        }

        if ( $io->{publications} ) {
            my ( $pmids_ref, $non_pmids_ref ) = $self->resolve_references(
                $strain->{pubmedid},
                $strain->{internal_db_id},
                $strain->{other_references}
            );

            my @pmids     = @{$pmids_ref};
            my @non_pmids = @{$non_pmids_ref};

            if (@pmids) {
                my @data;
                for my $pmid (@pmids) {
                    if ($pmid) {
                        my $s = sprintf "%s\t%d", $dbs_id, $self->trim($pmid);
                        push @data, $s;
                        $stats->{publications} = $stats->{publications} + 1;
                    }
                }
                my $outstr = join( "\n", @data );
                $io->{publications}->write( $outstr . "\n" ) if $outstr;
            }
            if (@non_pmids) {
                my @data;
                for my $non_pmid (@non_pmids) {
                    if ($non_pmid) {
                        my $s = sprintf "%s\t%s", $dbs_id,
                            $self->trim($non_pmid);
                        push @data, $s;
                        $stats->{other_refs} = $stats->{other_refs} + 1;
                    }
                }
                my $outstr = join( "\n", @data );
                $io->{other_refs}->write( $outstr . "\n" ) if $outstr;
            }
        }

        if ( $strain->{genotype} ) {
            my $genotype = $self->trim( $strain->{genotype} );
            if ( exists $io->{genotype} ) {
                $genotype =~ s/(,\W|,)/,/g;
                my $s = sprintf "%s\t%s\t%s\n", $dbs_id, $dscg_id, $genotype;
                $io->{genotype}->write($s);
                $stats->{genotype} = $stats->{genotype} + 1;
            }
            $dscg = $dscg + 1;
        }
        else {
            if ( $self->has_strain_genotype($dbs_id) ) {
                my $genotype = $self->get_strain_genotype($dbs_id);
                if ( $genotype =~ m/^[V0-9]{6}/ ) {
                    my $strain_name = $genotype;
                    my $genotype = $self->_get_genotype_for_V_strain($dbs_id);
                }
                $genotype =~ s/(,\W|,)/,/g;
                my $s = sprintf "%s\t%s\t%s\n", $dbs_id, $dscg_id, $genotype;
                $io->{genotype}->write($s);
                $stats->{genotype} = $stats->{genotype} + 1;
            }
            $dscg = $dscg + 1;
        }

        if ( exists $io->{phenotype} ) {
            my @phenotypes = $self->find_phenotypes($dbs_id);
            for my $phenotype (@phenotypes) {
                my @row;
                push @row, $dbs_id;
                push @row, $phenotype->[0];    # Phenotype term

                # Environment term
                if ( $phenotype->[1] ) {
                    push @row, $phenotype->[1];
                }
                else {
                    push @row, '';
                }

                # Assay term
                if ( $phenotype->[2] ) {
                    push @row, $phenotype->[2];
                }
                else {
                    push @row, '';
                }

                # PMID
                push @row, $phenotype->[3];

                # Phenotype notes
                if ( $phenotype->[4] ) {
                    my $phenotype_note = $self->trim( $phenotype->[4] );
                    $phenotype_note =~ s/[\n\r]/ /g;
                    push @row, $phenotype_note;
                }
                else {
                    push @row, '';
                }

                my $s = join( "\t", @row );
                $io->{phenotype}->write( sprintf "%s\n", $s );
                $stats->{phenotype} = $stats->{phenotype} + 1;
            }
        }

        if ( exists $io->{genes} ) {
            my $strain_gene_rs
                = $self->legacy_schema->resultset('StrainGeneLink')
                ->search( { strain_id => $strain->{id} }, { cache => 1 } );
            $strain_gene_rs->result_class(
                'DBIx::Class::ResultClass::HashRefInflator');
            my @data;
            while ( my $strain_gene = $strain_gene_rs->next ) {
                my $gene_id
                    = $self->find_gene_id( $strain_gene->{feature_id} );
                my $s = sprintf "%s\t%s", $dbs_id, $gene_id;
                push @data, $s;
                $stats->{genes} = $stats->{genes} + 1;
            }
            my $outstr = join( "\n", @data );
            $io->{genes}->write( $outstr . "\n" ) if $outstr;
        }

        if ( exists $io->{characteristics} ) {
            my $strain_char_rs
                = $self->legacy_schema->resultset('StrainCharCvterm')
                ->search( { strain_id => $strain->{id} }, { cache => 1 } );
            $strain_char_rs->result_class(
                'DBIx::Class::ResultClass::HashRefInflator');
            my @data;
            while ( my $strain_char = $strain_char_rs->next ) {
                my $cvterm_name
                    = $self->find_cvterm_name( $strain_char->{cvterm_id} );
                my $s = sprintf "%s\t%s", $dbs_id, $cvterm_name;
                push @data, $s;
                $stats->{characteristics} = $stats->{characteristics} + 1;
            }
            my $outstr = join( "\n", @data );
            $io->{characteristics}->write( $outstr . "\n" ) if $outstr;
        }

        if ( exists $io->{parent} ) {
            if ( $strain->{parental_strain} ) {
                my $parent = $self->trim( $strain->{parental_strain} );

                my @dbs_id_2 = $parent =~ m/(DBS[0-9]{7})/;
                if (@dbs_id_2) {
                    for my $dbs_id2 (@dbs_id_2) {
                        my $s = sprintf "%s\t%s\n", $dbs_id, $dbs_id2;
                        $io->{parent}->write($s);
                        $stats->{parent} = $stats->{parent} + 1;
                    }
                }
                else {
                    my @strains = $self->find_strain($parent);
                    if (@strains) {
                        for my $str (@strains) {
                            my $dbs_id_2
                                = $self->find_dbxref_accession( $str->[0] );
                            my $outstr = sprintf "%s\t%s", $dbs_id, $dbs_id_2;
                            $outstr = $outstr . "\t" . $str->[1]
                                if $str->[1];
                            $outstr = $outstr . "\n";
                            $io->{parent}->write($outstr);
                            $stats->{parent} = $stats->{parent} + 1;
                        }
                    }
                    else {
                        $io->{parent}
                            ->write( $dbs_id . "\t" . $parent . "\n" );
                        $stats->{parent} = $stats->{parent} + 1;
                    }
                }
            }
        }

        if ( exists $io->{props} ) {
            my @data;
            my $mm = $strain->{mutagenesis_method};
            if ($mm) {
                $mm =~ s/\?//;
                $mm = $self->trim($mm);
                if ( $self->has_mutagenesis_method($mm) ) {
                    my $s = sprintf "%s\tmutagenesis method\t%s", $dbs_id,
                        $self->get_mutagenesis_method($mm);
                    push @data, $s;
                    $stats->{props} = $stats->{props} + 1;
                }
            }
            my $gm = $strain->{mutant_type};
            if ($gm) {
                my $mutant_type = $self->find_cvterm_name($gm);
                my $s = sprintf "%s\tmutant type\t%s", $dbs_id, $mutant_type;
                push @data, $s;
                $stats->{props} = $stats->{props} + 1;
            }
            my @synonyms = $self->get_synonyms( $strain->{id} );
            if (@synonyms) {
                for my $synonym (@synonyms) {
                    my $s = sprintf "%s\tsynonym\t%s", $dbs_id, $synonym;
                    push @data, $s;
                    $stats->{props} = $stats->{props} + 1;
                }
            }
            my $outstr = join( "\n", @data );
            $io->{props}->write( $outstr . "\n" ) if $outstr;
        }

        if ( exists $io->{plasmid} ) {
            if ( $strain->{plasmid} ) {
                my $pl_name = $self->trim( $strain->{plasmid} );
                my @plasmids;
                if ( length($pl_name) > 1 ) {
                    if ( $pl_name =~ /,/ ) {
                        $pl_name
                            =~ s/(\(Lee and Falkow, 1998\)|\(partially impaired in retrieval\))//;
                        @plasmids = split( /,/, $pl_name );
                    }
                    else {
                        $plasmids[0] = $pl_name;
                    }
                    for my $plasmid (@plasmids) {
                        $plasmid = $self->trim($plasmid);
                        my $plasmid_id = $self->find_plasmid($plasmid);
                        my $dbp_id = sprintf( "DBP%07d", $plasmid_id )
                            if ( $plasmid_id and $plasmid_id != 0 );
                        $plasmid = $dbp_id if $dbp_id;
                        $io->{plasmid}
                            ->write( $dbs_id . "\t" . $plasmid . "\n" );
                        $stats->{plasmid} = $stats->{plasmid} + 1;
                    }
                }
            }
        }

    }

    for my $key ( keys $stats ) {
        $self->logger->info(
            "Exported " . $stats->{$key} . " entries for " . $key );
    }
    return;
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/\t/ /;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    $s =~ s/[\n\r]/ /;
    $s =~ s/\s+$//;
    return $s;
}

sub _create_files {
    my ($self) = @_;
    my $io;
    my $stats;

    $self->logger->info( "Data for [@{$self->data}] will be exported to "
            . $self->output_dir
            . " folder" );

    for my $data_type ( @{ $self->data } ) {
        my $file_obj
            = IO::File->new(
            $self->output_dir . "/strain_" . $data_type . ".tsv", 'w' );
        $io->{$data_type}    = $file_obj;
        $stats->{$data_type} = 0;

        if ( $data_type eq 'publications' ) {
            my $data_type_ = "other_refs";
            my $file_obj_
                = IO::File->new(
                $self->output_dir . "/strain_publications_no_pubmed.tsv",
                'w' );
            $io->{$data_type_}    = $file_obj_;
            $stats->{$data_type_} = 0;
        }
        if ( $data_type eq 'genotype' ) {
            $self->_find_strain_genotypes();
        }
        if ( $data_type eq 'genotype' or $data_type eq 'genes' ) {
            $self->_find_strain_genes();
        }
    }
    return ( $io, $stats );
}

1;

__END__

=head1 NAME

Modware::Dump::Command::dictystrain - Dump data for dicty strains 

=head1 VERSION

version 0.0.1

=head1 SYNOPSIS

	perl modware-dump dictystrain -c config.yaml  

	perl modware-dump dictystrain -c config.yaml --data inventory --data phenotype 

=head1 REQUIRED ARGUMENTS

-c, --configfile Config file with required arguments

=head1 DESCRIPTION

=head1 AUTHOR 
=head1 LICENSE AND COPYRIGHT

=cut
