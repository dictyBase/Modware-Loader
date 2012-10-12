package Modware::Role::Loggable;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Log::Log4perl;
use Log::Log4perl::Appender;
use Log::Log4perl::Level;
use Log::Log4perl::Layout::SimpleLayout;
use Log::Log4perl::Layout::PatternLayout;
use Log::Log4perl::Level;
use Moose::Util::TypeConstraints;

# Module implementation
#

has 'extended_logger_layout' => (
    is      => 'ro',
    isa     => 'Str',
    default => '[%d{MM-dd-yyyy hh:mm:ss}] %p > %F{1}:%L - %m%n', 
    lazy => 1
);

has 'use_extended_layout' => ( is => 'rw',  isa => 'Bool',  default => 0);

has 'output_logger' => (
    is         => 'rw',
    isa        => 'Log::Log4perl::Logger',
    lazy_build => 1,
);

has 'logger' => (
    is         => 'ro',
    isa        => 'Log::Log4perl::Logger',
    lazy => 1,
    default => sub {
    	my ($self) = @_;
    	return $self->output_logger;
    }
);

has 'log_level' => (
    is            => 'rw',
    isa           => 'Str', 
    lazy          => 1,
    default       => 'error',
    documentation => 'Log level of the logger,  default is error'
);

sub _build_output_logger {
    my ($self) = @_;

    my $appender
        = Log::Log4perl::Appender->new(
        'Log::Log4perl::Appender::ScreenColoredLevels',
        'stderr' => 1 );

    my $layout = $self->use_extended_layout ? Log::Log4perl::Layout::PatternLayout->new(
    	$self->extended_logger_layout
    ): Log::Log4perl::Layout::SimpleLayout->new;
    $appender->layout( $layout);

    my $log = Log::Log4perl->get_logger(__PACKAGE__);
    $log->add_appender($appender);
    my $numval = Log::Log4perl::Level::to_priority( uc $self->log_level );
    $log->level($numval);
    return $log;
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Role::Loggable - A Moose role to provide Log::Log4perl based logging ability to consuming classes


=head1 SYNOPSIS

package MyClass;
use Moose;
with 'Modware::Role::Loggable';


sub execute {

   my ($self) = @_;
   my $logger = $self->output_logger;

   $logger->info('what is happening');
   $logger->error('I have no idea');
}


=head2 ATTRIBUTES

=over

=item  output_logger - To get an instance of Log::Log4perl,  output goes to STDERR

=back
