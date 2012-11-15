package Modware::Load::Command::bioportalobo2chado;
use strict;
use namespace::autoclean;
use Moose;
use BioPortal::WebService;
use IO::Async::Loop;
use IO::Async::Function;
use feature qw/say/;
use Data::Dumper;
extends qw/Modware::Load::Chado/;

has 'apikey' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'An API key for bioportal'
);

has 'ontology' => (
    is            => 'rw',
    isa           => 'Str',
    required      => 1,
    documentation => 'Name of the ontology for loading in Chado'
);

sub execute {
    my ($self) = @_;
    my $bioportal = BioPortal::WebService->new( apikey => $self->apikey );
    my $onto      = $bioportal->get_ontology( $self->ontology );
    my $itr       = $onto->get_all_terms;

    my $total     = $itr->total_page;
    my $intervals = $self->make_intervals($total, 10);
    say Dumper $intervals;
    exit;

    my $loop = IO::Async::Loop->new;
    my $func = IO::Async::Function->new(
        code => sub {
            $self->fetch_terms(@_);
        }, 
        min_workers => 3, 
        max_workers => 5
    );
    $loop->add($func);

    my $counter = 0;
    for my $i ( 0 .. 2 ) {
        my $slice = $itr->slice( @{ $intervals[$i] } );
        $func->call(
            args      => [$slice],
            on_return => sub { 
              $self->load_terms(@_); 
              if ($counter == 2) {
              	$loop->stop;
              }
              $counter++;
            },
            on_error  => sub { $self->throw_error(@_) }
        );
    }
}

sub fetch_terms {
	my ($self, $itr) = @_;
	my $all_terms;
	while(my $term = $itr->next_term) {
		push @$all_terms, $term;
	}
	return $all_terms;
}

sub load_terms {
	my ($self, $all_terms) = @_;
	say $_->name for @$all_terms;
}

sub throw_error {
	my ($self, $error) = @_;
	warn "could not get terms $error\n";
}

sub make_intervals {
	my ($self, $end, $increment) = @_;
	my $slices;
	my $start = 1;
	while(1) {
		my $next = $start + $increment;
		if ($next >= $end) {
			push @$slices, [$start, $end];
			last;
		}
		push @$slices, [$start, $next];
		$start = $next + 1;
	}
	return $slices;
}

__END__

=head1 NAME

Modware::Load::Command::bioportalobo2chado -  Load ontology from NCBO bioportal to chado database
 
