package Modware::Export::Command::chado2fasta;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
extends qw/Modware::Export::Chado/;

# Module implementation
#


has '_type2retrieve' => (
	is => 'rw', 
	isa => 'HashRef[Coderef]', 
	traits => [qw/Hash/], 
	handles => {
		'all_type2features' => 'keys', 
		'get_type2feature_coderef' => 'get', 
		'register_type2feature_handler' => 'set', 
		'has_type2feature_handler' => 'defined'
	}, 
	lazy => 1, 
	default => sub {
		my ($self) = @_;
		return {
			'supercontig' => sub {$self->get_supercontig(@_)}, 
			'chromosome' => sub {$self->get_chromosome(@_)}, 
			'gene' => sub {$self->get_gene(@_)}, 
			'cds' => sub {$self->get_cds(@_)}, 
			'ncRNA' => sub {$self->get_ncrna(@_)}, 
			'mRNA' => sub {$self->get_mRNA(@_)}, 
			'polypeptide' => sub {$self->get_polypeptide(@_)}
		};
	}
);

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Export GFF3 file from chado database

