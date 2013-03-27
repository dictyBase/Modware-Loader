package Modware::Role::Command::WithEmail;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Email::Sender::Simple qw/sendmail/;
use Email::Simple;
use Email::Sender::Transport::SMTP;
use Moose::Util::TypeConstraints;
use Email::Valid;
use Carp;

# Module implementation
#

requires 'execute';
requires 'current_logger';
requires 'msg_appender';

after 'execute' => sub {
    my ($self) = @_;
    if ( $self->send_email ) {
    	carp "Need *host* to send e-mail\n" if !$self->has_host;
        if ( $self->has_msg_appender ) {
            my $msg = $self->msg_appender->string;
            $self->robot_email($msg);
        }
        else {
            $self->current_logger->warn(
                "No string/message log appender defined: e-mail will not be send"
            );
        }
    }
};

subtype 'Email' => as 'Str' => where { Email::Valid->address($_) };

has 'send_email' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
    documentation =>
        'Whether or not the program will email the log,  default is true'
);

has 'host' => (
    is            => 'rw',
    isa           => 'Str',
    documentation => 'SMTP host for sending e-mail,  required if *send_email* is set', 
    predicate => 'has_host'
);

has 'to' => (
    is      => 'rw',
    isa     => 'Email',
    default => 'dictybase@northwestern.edu',
    documentation =>
        'e-mail parameter,  default is dictybase@northwestern.edu'
);

has 'from' => (
    is      => 'rw',
    isa     => 'Email',
    default => 'dictybase@northwestern.edu',
    documentation =>
        'e-mail parameter,  default is dictybase@northwestern.edu'
);

has 'subject' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'e-mail from robot',
    documentation =>
        'e-mail parameter,  default is *email from chicken robot*'
);

sub robot_email {
    my ( $self, $msg ) = @_;
    my $trans
        = Email::Sender::Transport::SMTP->new( { host => $self->host } );
    my $email = Email::Simple->create(
        header => [
            From    => $self->from,
            To      => $self->to,
            Subject => $self->subject
        ],
        body => $msg
    );

    sendmail( $email, { transport => $trans } );
}

1;    # Magic true value required at end of module

