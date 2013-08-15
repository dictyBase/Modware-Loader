
package Modware::Dump::Command::dictystrain;

use strict;

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

    my $strain_rs = $self->legacy_schema->resultset('StockCenter')->search(
        {},
        {   select => [
                qw/id strain_name strain_description species dbxref_id pubmedid phenotype genotype other_references internal_db_id mutagenesis_method mutant_type parental_strain plasmid/
            ],
            cache => 1
        }
    );

    my $dscg = 1;

    while ( my $strain = $strain_rs->next ) {

        my $dbs_id = $self->find_dbxref_accession( $strain->dbxref_id );
        my $dscg_id = sprintf( "DSC_G%07d", $dscg );

        if ( exists $io->{strain} ) {
            my $row;
            $row->{0} = $dbs_id;
            $row->{1} = $self->trim( $strain->strain_name );
            if ( $strain->species ) {
                $row->{2} = $strain->species;
            }
            else {
                $row->{2} = '';
            }

            if ( $strain->strain_description ) {
                my $strain_desc = $self->trim( $strain->strain_description );
                $strain_desc =~ s/\r\n//g;
                $row->{3} = $strain_desc;
            }
            else {
                $row->{3} = '';
            }

            my $s = join(
                "\t",
                map( $row->{$_} => sort { $a <=> $b }
                        keys %{$row} )
            );
            $io->{strain}->write( $s . "\n" );
            $stats->{strain} = $stats->{strain} + 1;
        }

        if ( exists $io->{inventory} ) {
            my $strain_invent_rs = $self->find_strain_inventory($dbs_id);
            if ($strain_invent_rs) {
                while ( my $strain_invent = $strain_invent_rs->next ) {
                    my $row;
                    $row->{0} = $dbs_id;
                    if ( $strain_invent->location ) {
                        $row->{1} = $self->trim( $strain_invent->location );
                    }
                    else { $row->{1} = '' }

                    my $color
                        = $self->trim( ucfirst( $strain_invent->color ) );
                    if ( length($color) > 1 ) {
                        $row->{2} = $color;
                    }
                    else { $row->{2} = '' }

                    if (    $strain_invent->no_of_vials
                        and $strain_invent->no_of_vials =~ /^\d+$/ )
                    {
                        $row->{3}
                            = $self->trim( $strain_invent->no_of_vials );
                    }
                    else { $row->{3} = '' }

                    if ( $strain_invent->obtained_as ) {
                        my $strain_obtained_as
                            = $self->trim( $strain_invent->obtained_as );
                        if ( length($strain_obtained_as) > 1 ) {
                            $row->{4} = $strain_obtained_as;
                        }
                        else { $row->{4} = '' }
                    }
                    else { $row->{4} = '' }

                    my $strain_stored_as = $strain_invent->stored_as;
                    if ( $strain_stored_as and length($strain_stored_as) > 1 )
                    {
                        $strain_stored_as =~ s/\?//g;
                        $strain_stored_as = $self->trim($strain_stored_as);
                        if ( length($strain_stored_as) > 1 ) {
                            $row->{5} = $strain_stored_as;
                        }
                        else { $row->{5} = '' }
                    }
                    else { $row->{5} = '' }

                    if ( $strain_invent->storage_date ) {
                        $row->{6}
                            = $self->trim( $strain_invent->storage_date );
                    }
                    else { $row->{6} = '' }

                    my $s = join(
                        "\t",
                        map( $row->{$_} => sort { $a <=> $b }
                                keys %{$row} )
                    );
                    $io->{inventory}->write( $s . "\n" );
                    $stats->{inventory} = $stats->{inventory} + 1;
                }
            }
        }

        if ( $io->{publications} ) {
            my ( $pmids_ref, $non_pmids_ref )
                = $self->resolve_references( $strain->pubmedid,
                $strain->internal_db_id, $strain->other_references );

            my @pmids     = @{$pmids_ref};
            my @non_pmids = @{$non_pmids_ref};

            if (@pmids) {
                my $outstr = '';
                foreach my $pmid (@pmids) {
                    if ($pmid) {
                        $outstr
                            = $outstr
                            . $dbs_id . "\t"
                            . $self->trim($pmid) . "\n";
                        $stats->{publications} = $stats->{publications} + 1;
                    }
                }
                $io->{publications}->write($outstr);
            }
            if (@non_pmids) {
                my $outstr = '';
                foreach my $non_pmid (@non_pmids) {
                    if ($non_pmid) {
                        $outstr
                            = $outstr
                            . $dbs_id . "\t"
                            . $self->trim($non_pmid) . "\n";
                        $stats->{other_refs} = $stats->{other_refs} + 1;
                    }
                }
                $io->{other_refs}->write($outstr);
            }
        }

        if ( $strain->genotype ) {
            my $genotype = $self->trim( $strain->genotype );
            if ( exists $io->{genotype} ) {
                $genotype =~ s/(,\W|,)/,/g;

                # $genotype =~ s/\?$//g;

                $io->{genotype}->write(
                    $dbs_id . "\t" . $dscg_id . "\t" . $genotype . "\n" );
                $stats->{genotype} = $stats->{genotype} + 1;
            }
            $dscg = $dscg + 1;
        }

        if ( exists $io->{phenotype} ) {
            my @phenotypes = $self->find_phenotypes($dbs_id);
            foreach my $phenotype (@phenotypes) {
                $io->{phenotype}
                    ->write( $dbs_id . "\t" . $phenotype->[0] . "\n" );
                $stats->{phenotype} = $stats->{phenotype} + 1;
            }

            if ( $strain->phenotype ) {
                my @phenotypes_jakob = split( /[,;]/, $strain->phenotype );
                foreach my $phenotype (@phenotypes_jakob) {
                    $phenotype = $self->trim($phenotype);
                    if (   !$self->is_strain_genotype($phenotype)
                        && !$self->is_strain_characteristic($phenotype) )
                    {
                        $io->{phenotype_jakob}
                            ->write( $dbs_id . "\t" . $phenotype . "\n" )
                            if ($phenotype);

                    }
                }
            }
        }

        if ( exists $io->{genes} ) {
            my $strain_gene_rs
                = $self->legacy_schema->resultset('StrainGeneLink')
                ->search( { strain_id => $strain->id }, { cache => 1 } );
            while ( my $strain_gene = $strain_gene_rs->next ) {
                my $gene_id = $self->find_gene_id( $strain_gene->feature_id );
                $io->{genes}->write(
                    $dbs_id . "\t" . $gene_id . "\t" . $dscg_id . "\n" );
                $stats->{genes} = $stats->{genes} + 1;
            }
        }

        if ( exists $io->{characteristics} ) {
            my $strain_char_rs
                = $self->legacy_schema->resultset('StrainCharCvterm')
                ->search( { strain_id => $strain->id }, { cache => 1 } );
            while ( my $strain_char = $strain_char_rs->next ) {
                my $cvterm_name
                    = $self->find_cvterm_name( $strain_char->cvterm_id );
                $io->{characteristics}
                    ->write( $dbs_id . "\t" . $cvterm_name . "\n" );
                $stats->{characteristics} = $stats->{characteristics} + 1;
            }
        }

        if ( exists $io->{parent} ) {
            if ( $strain->parental_strain ) {
                my $P        = $self->trim( $strain->parental_strain );
                my @dbs_id_2 = $P =~ m/(DBS[0-9]{7})/;
                if (@dbs_id_2) {
                    foreach my $dbs_id2 (@dbs_id_2) {
                        $io->{parent}
                            ->write( $dbs_id . "\t" . $dbs_id2 . "\n" );
                    }
                }
                else {
                    my @strains = $self->find_strain($P);
                    if (@strains) {
                        foreach my $str (@strains) {
                            my $dbs_id_2
                                = $self->find_dbxref_accession( $str->[0] );
                            my $outstr = $dbs_id . "\t" . $dbs_id_2;
                            $outstr = $outstr . "\t" . $str->[1] if $str->[1];
                            $outstr = $outstr . "\n";
                            $io->{parent}->write($outstr);
                        }
                    }
                    else {
                        $io->{parent}->write( $dbs_id . "\t" . $P . "\n" );
                    }
                }
            }
        }

        if ( exists $io->{props} ) {
            my $mm = $strain->mutagenesis_method;
            if ($mm) {
                $mm =~ s/\?//;
                $mm = $self->trim($mm);
                if ( $self->has_mutagenesis_method($mm) ) {
                    $io->{props}->write( $dbs_id . "\t"
                            . 'mutagenesis method' . "\t"
                            . $self->get_mutagenesis_method($mm)
                            . "\n" );
                    $stats->{props} = $stats->{props} + 1;
                }
            }

            my $gm = $strain->mutant_type;
            if ($gm) {
                my $mutant_type = $self->find_cvterm_name($gm);
                $io->{props}->write( $dbs_id . "\t"
                        . 'mutant type' . "\t"
                        . $mutant_type
                        . "\n" );
                $stats->{props} = $stats->{props} + 1;
            }

            my @synonyms = $self->get_synonyms( $strain->id );
            if (@synonyms) {
                foreach my $synonym (@synonyms) {
                    $io->{props}->write(
                        $dbs_id . "\t" . 'synonym' . "\t" . $synonym . "\n" );
                    $stats->{props} = $stats->{props} + 1;
                }
            }
        }

        if ( exists $io->{plasmid} ) {
            if ( $strain->plasmid ) {
                my $pl_name = $self->trim( $strain->plasmid );
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
                    foreach my $plasmid (@plasmids) {
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

    foreach my $key ( keys $stats ) {
        $self->logger->info(
            "Exported " . $stats->{$key} . " entries for " . $key );
    }
    return;
}

sub trim {
    my ( $self, $s ) = @_;
    $s =~ s/^\s+//;
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

    foreach my $f ( @{ $self->data } ) {
        my $file_obj
            = IO::File->new( $self->output_dir . "/strain_" . $f . ".txt",
            'w' );
        $io->{$f}    = $file_obj;
        $stats->{$f} = 0;

        if ( $f eq 'publications' ) {
            my $f_ = "other_refs";
            my $file_obj_
                = IO::File->new(
                $self->output_dir . "/strain_publications_no_pubmed.txt",
                'w' );
            $io->{$f_}    = $file_obj_;
            $stats->{$f_} = 0;
        }
        if ( $f eq 'phenotype' ) {
            my $f_ = "phenotype_jakob";
            my $file_obj_
                = IO::File->new(
                $self->output_dir . "/strain_phenotype_jakob.txt", 'w' );
            $io->{$f_} = $file_obj_;
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
