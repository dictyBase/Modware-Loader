package Modware::Loader::Role::Temp::Obo;


# Other modules:
use strict;
use namespace::autoclean;
use Moose::Role;
use Moose::Util qw/ensure_all_roles/;
use DBI;
use Modware::Loader::Schema::Result::Temp::Obo;

# Module implementation
#

after 'dsn' => sub {
	my ($self, $value) = @_;
	return if !$value;
	my ($schema, $driver) = DBI->parse_dsn($value);
    $driver = ucfirst(lc $driver);

    $self->meta->make_mutable;
    ensure_all_roles($self, 'Modware::Loader::Role::Temp::Obo::'.$driver);
    $self->meta->make_immutable;

    $self->add_on_connect($_) for $self->on_connect_sql;
    $self->add_on_disconnect($_) for $self->on_disconnect_sql;
};


sub inject_tmp_schema {
	my $self = shift;
	$self->chado->register_class('Temp' => 'Modware::Loader::Schema::Result::Temp::Obo');
}

sub load_data {
}



1;    # Magic true value required at end of module

