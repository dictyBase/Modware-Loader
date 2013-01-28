package Modware::Role::Command::CanCompress;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use IO::Compress::Gzip qw($GzipError gzip);

# Module implementation
#

requires 'output';
has 'compressed_output' => ( is => 'rw',  isa => 'Str');

after 'execute' => sub  {
	my $self = shift;
	my $logger = $self->logger;
	my $compressed;
	if (gzip $self->output => \$compressed) {
		$logger->info("compressed $input");
		$self->compressed_output($compressed)
	} 
	else {
		$logger->logdie($GzipError);
	}
};


1;
