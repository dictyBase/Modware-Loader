package Modware::Role::Command::Convert::Resource::gp2protein;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Carp;
use Path::Class::File;

# Module implementation
#

requires 'location';

has '_id_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    default => sub { {} },
    handles => {
        '_add_id'      => 'set',
        '_get_mod_id'  => 'get',
        '_has_id'      => 'defined',
        '_clear_stack' => 'clear'
    }
);

sub init_resource {
    my ($self) = @_;
    my $input = Path::Class::File->new( $self->location );
    croak "cannot slurp file more than 250 MB in size\n"
        if $input->stat->size > ( 250 * 1024 * 1024 );
    my $handler = $input->openr;
    while ( my $line = $handler->getline ) {
        next if $line =~ /^\!/;
        chomp $line;
        my ( $mod, $map ) = split /\t/, $line;
        my ($mod_id) = ( ( split /:/, $mod ) )[1];
        for my $other ( split /\;/, $map ) {
            my ($id) = ( ( split /:/, $other ) )[1];
            $self->_add_id( $id, $mod_id );
        }
    }
    $handler->close;
}

sub is_present {
    my ( $self, $id ) = @_;
    return 1 if $self->_has_id($id);
}

sub translate {
    my ( $self, $id ) = @_;
    return $self->_get_mod_id($id);
}

1;    # Magic true value required at end of module

