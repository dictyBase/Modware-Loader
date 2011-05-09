package Modware::Role::Command::CanCompress;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use MooseX::Params::Validate;
use IO::Compress::Gzip qw($GzipError gzip);

# Module implementation
#

requires 'current_logger';

sub compress {
	my $self = shift;
	my ($input,  $output) = validated_list(
		\@_, 	
		input => { isa => 'Str'}, 
		output => { isa => 'Str'}
	);

	my $logger = $self->current_logger;
	if (gzip $input => $output) {
		$logger->info("compressed $input to $output");
	} 
	else {
		$logger->error($GzipError);
	}
}


1;    # Magic true value required at end of module

