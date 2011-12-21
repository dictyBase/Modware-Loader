package Modware::Role::Command::WithReportLogger;

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
    traits  => [qw/NoGetopt/],
    builder => '_build_logger'
);

sub _build_logger {
    my $self = shift;
    my $options;
    $options->{ident} = $self->meta->name;
    my $logfile
        = $self->has_logfile and $self->can('logfile')
        ? $self->logfile
        : undef;
   if ($logfile) {
        my $t = Time::Piece->new;
        $options->{to_file}  = 1;
        $options->{log_file} = $t->ymd('-') . "_$logfile";
    }
    else {
        $options->{to_stderr} = 1;
    }
    return $logfile;
}


1;    # Magic true value required at end of module

