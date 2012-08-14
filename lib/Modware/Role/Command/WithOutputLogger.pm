package Modware::Role::Command::WithOutputLogger;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Log::Log4perl;
use Log::Log4perl::Appender;
use Log::Log4perl::Level;

# Module implementation
#

has 'output_logger' => (
    is         => 'rw',
    isa        => 'Log::Log4perl::Logger',
    traits     => [qw/NoGetopt/],
    lazy_build => 1,
);

sub _build_output_logger {
    my ($self) = @_;

    my $appender
        = Log::Log4perl::Appender->new(
        'Log::Log4perl::Appender::ScreenColoredLevels',
        'stderr' => 1 );
    $appender->layout( Log::Log4perl::Layout::SimpleLayout->new );

    my $log = Log::Log4perl->get_logger(__PACKAGE__);
    $log->add_appender($appender);
    $log->level($DEBUG);
    return $log;
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Role::Command::WithOuputLogger - A Moose role to print colorful message in MooseX::App::Cmd application classes


=head1 SYNOPSIS

package YourApp::Cmd::Command::baz;
use Moose;
extends qw/MooseX::App::Cmd::Command/;

with 'Modware::Role::Command::WithOutputLogger';


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
