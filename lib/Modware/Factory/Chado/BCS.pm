package Modware::Factory::Chado::BCS;

# Other modules:
use Class::Load qw/load_class/;
use namespace::autoclean;
use Moose;

# Module implementation
#

has 'engine' => ( isa => 'Str',  is => 'rw');

sub get_engine {
    my ( $self, $engine ) = @_;
    $engine  = $self->engine if !$engine;
	die "need a engine name\n" if !$engine;

	my $class_name = 'Modware::DataSource::Chado::BCS::Engine::'.ucfirst(lc $engine);
	load_class($class_name);
    return $class_name->new();
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

