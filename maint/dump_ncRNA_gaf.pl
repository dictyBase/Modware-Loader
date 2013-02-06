
use strict;

package Dicty::GAF::ncRNA::Export;

use Bio::Chado::Schema;
use IO::File;
use LWP::Simple;
use Moose;
use MooseX::Attribute::Dependent;
with 'MooseX::Getopt';

has [qw/dsn user password/] => (
    is  => 'rw',
    isa => 'Str',
);

has '_schema' => (
    is      => 'rw',
    isa     => 'Bio::Chado::Schema',
    default => sub {
        my ($self) = @_;
        return Bio::Chado::Schema->connect( $self->dsn, $self->user,
            $self->password, { LongReadLen => 2**25 } );
    },
    lazy       => 1,
    dependency => All [ 'user', 'password', 'dsn' ],
);

has 'id_list' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'DDB_G Ids for ncRNA'
);

has 'gaf' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'GAF file containing ncRNA annotations'
);

sub run {
    my ($self) = @_;

    #my @accessions = $self->get_ncRNA_accessions();

    my @accessions;
    my $to_find = IO::File->new;
    $to_find->open( $self->id_list );
    while ( my $id = $to_find->getline ) {
        chomp($id);
        push @accessions, $id;
    }

    my $gaf_io = IO::File->new;
    $gaf_io->open( $self->gaf );
    while ( my $line = $gaf_io->getline ) {
        chomp($line);
        my @gaf_vals = split( "\t", $line );
        foreach (@accessions) {
            if ( $line =~ /$_/x ) {
                print $line. "\n";
            }
        }
    }
}

sub get_ncRNA_accessions {
    my ($self) = @_;

    my $gene_rs = $self->_schema->resultset('Sequence::Feature')
        ->search( { 'type.name' => 'gene' }, { join => 'type' } );

    my $ncRNA_rs
        = $gene_rs->search_related( 'feature_relationship_objects', {}, {} )
        ->search_related(
        'subject',
        {   -or => [
                'type_2.name' => { -in => [qw/ncRNA rRNA snRNA/] },
                'type_2.name' =>
                    { -like => [qw/class%RNA RNase% SRP% %snoRNA%/] }
            ]
        },
        { join => [qw/type dbxref/], select => 'dbxref.accession' }
        );

   #    my $ncRNA_rs = $self->_schema->resultset('Sequence::Feature')->search(
   #        {   -or => [
   #                'type.name' =>
   #                    { -like => [qw/class%RNA RNase% SRP% %snoRNA%/] },
   #                'type.name' => [qw/ncRNA rRNA snRNA/]
   #            ]
   #        },
   #        { join => [qw/dbxref type/], select => 'dbxref.accession' }
   #    );

    my @accessions;
    while ( my $ncRNA = $ncRNA_rs->next ) {
        push @accessions, $ncRNA->dbxref->accession;
    }
    return @accessions;
}

1;

package main;
Dicty::GAF::ncRNA::Export->new_with_options->run;

__END__

=head1 NAME

dump_ncRNA_gaf.pl - Dump GO annotations for ncRNA

=head1 SYNOPSIS
	
perl dump_ncRNA_gaf.pl --id_list <ncRNA-DDB_G-Ids> --gaf <GAF-file> >> ncRNA.gaf

=cut
