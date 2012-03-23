package Modware::Role::Command::WithLogger;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Log::Log4perl;
use Log::Log4perl::Appender;
use Log::Log4perl::Appender::String;
use Log::Log4perl::Level;
use Moose::Util::TypeConstraints;

# Module implementation
#
has 'logfile' => (
    is            => 'rw',
    isa           => 'Str',
    predicate     => 'has_logfile',
    traits        => [qw/Getopt/],
    cmd_aliases   => 'l',
    documentation => 'Name of logfile,  default goes to STDERR'
);

has 'current_logger' => (
    is      => 'ro',
    isa     => 'Log::Log4perl::Logger',
    default => sub { Log::Log4perl->get_logger(__PACKAGE__) },
    lazy    => 1,
    traits  => [qw/NoGetopt/]
);

has 'log_appender' => (
    is     => 'rw',
    isa    => 'Log::Log4perl::Appender',
    traits => [qw/NoGetopt/],
);

has 'msg_appender' => (
    is        => 'rw',
    isa       => 'Log::Log4perl::Appender',
    traits    => [qw/NoGetopt/],
    predicate => 'has_msg_appender'
);

has 'log_level' => (
    is            => 'rw',
    isa           => enum(qw/debug error fatal info warn/),
    lazy          => 1,
    default       => 'error',
    documentation => 'Log level of the logger,  default is error'
);

sub dual_logger {
    my $self = shift;
    my $logger
        = $self->has_logfile
        ? $self->fetch_dual_logger( $self->logfile )
        : $self->fetch_dual_logger;
    $logger;
}

sub fetch_dual_logger {
    my ( $self, $file ) = @_;

    my $str_appender
        = Log::Log4perl::Appender->new( 'Log::Log4perl::Appender::String',
        name => 'message_stack' );
    $self->msg_appender($str_appender);

    my $appender;
    if ($file) {
        $appender = Log::Log4perl::Appender->new(
            'Log::Log4perl::Appender::File',
            filename => $file,
            mode     => 'clobber'
        );
    }
    else {
        $appender
            = Log::Log4perl::Appender->new(
            'Log::Log4perl::Appender::ScreenColoredLevels',
            );
    }
    $self->log_appender($appender);

    my $layout = Log::Log4perl::Layout::PatternLayout->new(
        "[%d{MM-dd-yyyy hh:mm}] %p > %F{1}:%L - %m%n");

    my $log = Log::Log4perl->get_logger(__PACKAGE__);
    $appender->layout($layout);
    $str_appender->layout($layout);
    $log->add_appender($str_appender);
    $log->add_appender($appender);
    $log->level($DEBUG);
    $log;
}

has 'logger' => (
    is      => 'rw',
    isa     => 'Log::Log4perl::Logger',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $logger
            = $self->has_logfile
            ? $self->fetch_logger( $self->logfile )
            : $self->fetch_logger;
        return $logger;
    }
);

sub fetch_logger {
    my ( $self, $file ) = @_;

    my $appender;
    if ($file) {
        $appender = Log::Log4perl::Appender->new(
            'Log::Log4perl::Appender::File',
            filename => $file,
            mode     => 'clobber'
        );
    }
    else {
        $appender
            = Log::Log4perl::Appender->new(
            'Log::Log4perl::Appender::ScreenColoredLevels',
            'stderr' => 1 );
    }

    my $layout = Log::Log4perl::Layout::PatternLayout->new(
        "[%d{MM-dd-yyyy hh:mm}] %p > %F{1}:%L - %m%n");

    my $log = Log::Log4perl->get_logger();
    $appender->layout($layout);
    $log->add_appender($appender);
    $log->level( '$' . uc $self->log_level );
    $log;
}

1;    # Magic true value required at end of module

