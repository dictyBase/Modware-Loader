
use strict;

package Modware::Role::Command::GOA::Dicty::AppendncRNA;

use autodie qw/open close/;
use File::ShareDir qw/module_file/;
use IO::File;
use Modware::Loader;
use Moose::Role;
use namespace::autoclean;

requires 'input';

before 'execute' => sub {
    my ($self) = @_;
    my $logger = $self->logger;
    my $input  = $self->input;
    $logger->logdie('No input found') if !$input;

    my $ncRNA_gaf_file
        = IO::File->new( module_file( 'Modware::Loader', 'dicty_ncRNA.gaf' ),
        'r' );

    my $writer = IO::File->new( $input, 'a' );
    while ( my $line = $ncRNA_gaf_file->getline ) {
        $writer->print($line);
    }
    $ncRNA_gaf_file->close;
    $writer->close;
};

1;
