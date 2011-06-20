package Modware::Role::Command::WithFlogger;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Log::Dispatchouli;
use Time::Piece;

# Module implementation
#
has 'logfile' => (
    is            => 'rw',
    isa           => 'Str',
    predicate     => 'has_logfile',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'l',
    documentation => 'Name of logfile,  default goes to STDIN'
);

has 'logger' => (
    is      => 'ro',
    isa     => 'Log::Dispatchouli',
    lazy    => 1,
    traits => [qw/NoGetopt/], 
    builder => '_build_logger'
);

sub _build_logger {
    my $self = shift;
    my $options;
    $options->{ident} = $self->meta->name;
    if ( $self->has_logfile ) {
        my $t = Time::Piece->new;
        $options->{to_file}  = 1;
        $options->{log_file} = $t->ymd . '-' . $self->logfile;
    }
    else {
        $options->{to_stderr} = 1;
    }
    return Log::Dispatchouli->new( $options );
}

1;    # Magic true value required at end of module

