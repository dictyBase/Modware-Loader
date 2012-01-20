package Modware::Export::Command::chado2gff3;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
extends qw/Modware::Export::Chado/;

# Module implementation
#

has 'organism' => (
    isa         => 'Str',
    is          => 'rw',
    traits      => [qw/Getopt/],
    required    => 1,
    cmd_aliases => 'org',
    documentation =>
        'Common name of the organism whose genomic features will be exported'
);

sub execute {
    my $self   = shift;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Export GFF3 file from chado database

