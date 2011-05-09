package Modware::Role::Command::WithLogger;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Log::Log4perl;
use Log::Log4perl::Appender;
use Log::Log4perl::Appender::String;
use Log::Log4perl::Level;

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

sub logger {
    my $self = shift;
    my $logger
        = $self->has_logfile
        ? $self->fetch_logger( $self->logfile )
        : $self->fetch_logger;
    $logger;
}

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
            );
    }

    my $layout = Log::Log4perl::Layout::PatternLayout->new(
        "[%d{MM-dd-yyyy hh:mm}] %p > %F{1}:%L - %m%n");

    my $log = Log::Log4perl->get_logger();
    $appender->layout($layout);
    $log->add_appender($appender);
    $log->level($DEBUG);
    $log;
}

1;    # Magic true value required at end of module

