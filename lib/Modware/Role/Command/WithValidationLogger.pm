package Modware::Role::Command::WithValidationLogger;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Log::Dispatchouli;
use Time::Piece;

# Module implementation
#
has 'validation_logfile' => (
    is            => 'rw',
    isa           => 'Str',
    predicate     => 'has_validation_logfile',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'vl',
    documentation => 'Name of logfile,  default goes to STDIN'
);


sub validation_logger_for {
	my ($self, $type) = @_;
	my $method = "_validation_$type_logger";
	return $self->$method;
}

has '_validation_info_logger' => (
    is      => 'ro',
    isa     => 'Log::Dispatchouli',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    default => sub {
    	my ($self) = @_;
    	return $self->_build_validation_logger('info');
    }
);

has '_validation_error_logger' => (
    is      => 'ro',
    isa     => 'Log::Dispatchouli',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
	default => sub {
    	my ($self) = @_;
    	return $self->_build_validation_logger('error');
    }

);

sub _build_validation_logger {
    my ($self, $type) = @_;
    my $options;
    $options->{ident} = $self->meta->name;
    my $logfile
        = $self->has_validation_logfile ? $self->validation_logfile
        : $self->has_logfile and $self->can('logfile') ? $self->logfile
        :                                                undef;
    if ($logfile) {
        my $t = Time::Piece->new;
        $options->{to_file}  = 1;
        $options->{log_file} = $t->ymd . "-$type-validation-$logfile";
    }
    else {
        $options->{to_stderr} = 1;
    }
    return Log::Dispatchouli->new($options);
}

1;    # Magic true value required at end of module

