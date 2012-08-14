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
    default       => 'debug',
    documentation => 'Log level of the logger,  default is error'
);

has 'logger_format' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    default => '%m%n', 
    lazy => 1
);

has 'extended_logger_format' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    default => '[%d{MM-dd-yyyy hh:mm}] %p > %F{1}:%L - %m%n', 
    lazy => 1
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
    my $layout = Log::Log4perl::Layout::PatternLayout->new($self->logger_format);

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
    my $numval = Log::Log4perl::Level::to_priority( uc $self->log_level );
    $log->level($numval);
    $log;
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Role::Command::WithLogger - A Moose role to integrate Log::Log4perl in MooseX::App::Cmd application classes


=head1 SYNOPSIS

package YourApp::Cmd::Command::baz;
use Moose;
extends qw/MooseX::App::Cmd::Command/;

with 'Modware::Role::Command::WithLogger';


sub execute {

   my ($self) = @_;
   my $logger = $self->logger;

   $logger->info('what is happening');
   $logger->error('I have no idea');
}

=head1 More examples

=head2 Change the logger's output style

=head2 Change the log level

=head2 Output log to a file

=head2 METHODS

The following public methods are exported in the consuming application command classes.

=over

=item logger - A Log::Log4perl object

=back


=head2 ATTRIBUTES

The following attributes are available in the command line as well as in the consuing
classes

=over

=item  logfile - Output to a given file,  default is STDERR. 

=item  log_level - Various log level,  could be one of debug, info,  error and fatal,
defaults to debug.

=back


These are only available in the consuming classes

=over

=item  current_logger - To get an instance of Log::Log4perl,  identical to logger method 

=item  log_appender

=item  msg_appender

=item  logger_format - default pattern layout for logging output

=item  extended_logger_format - another pattern layout for ouput,  for details please
consult L<Log::Log4perl::Layout::PatternLayout> 

=back
