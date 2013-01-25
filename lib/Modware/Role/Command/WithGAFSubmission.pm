package Modware::Role::Command::WithGAFSubmission;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use SVN::Client;
use File::Temp;
use File::Copy;
use File::Basename;
use File::Spec::Functions;

# Module implementation
#

requires 'compressed_output';

has 'submission_url' => (
    is      => 'rw',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return
              'svn+ssh://'
            . $self->gouser
            . '@ext.geneontology.org/share/go/svn/trunk/gene-associations/submission';
    }
);

has 'checkout_folder' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        return File::Temp->newdir;
    },
    documentation =>
        'The checkout folder of subversion repository,  defaults to a temporary folder'
);

has 'gouser' => (
    is  => 'rw',
    isa => 'Str', 
    documentation => 'username for go-svn repository'
);

after 'execute' => sub {
	my ($self) = @_;
	my $logger = $self->logger;
	$logger->debug("Starting checkout of go-svn");

	my $svn = SVN::Client->new;
	$svn->checkout($self->submission_url, $self->checkout_folder,  'HEAD',  0);
	copy $self->compressed_output, $self->checkout_folder;
	$svn->add(catfile($self->checkout_folder, basename $self->compressed_output, 0);
	$svn->commit($self->checkout_folder, 0);

	$logger->debug("commited ", $self->compressed_output,  " to go-svn");

};

1;    # Magic true value required at end of module

