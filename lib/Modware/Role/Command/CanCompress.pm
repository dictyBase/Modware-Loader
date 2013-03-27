package Modware::Role::Command::CanCompress;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use IO::Compress::Gzip qw($GzipError gzip);

# Module implementation
#

requires 'output';

has 'compressed_output' => ( is => 'rw', isa => 'Str' );

after 'execute' => sub {
    my $self   = shift;
    my $logger = $self->logger;
    $self->compressed_output( $self->output . ".gz" );

    my $status = gzip $self->output => $self->compressed_output
        or die "gzip failed: " . $GzipError . "\n";

    if ($status) {
        $logger->info('File successfully compressed');
    }
};

1;
