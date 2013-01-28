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

has 'submission_name' => (
    is => 'rw', 
    isa => 'Str', 
    default => 'gene_association.dictyBase.gz', 
    lazy => 1

);

after 'execute' => sub {
	my ($self) = @_;
	my $logger = $self->logger;

    $logger->debug("Saving compressed input to a temp file");
    my $tmpfh = File::Temp->new;
    my $filename = $tmpfh->filename;
    $tmpfh->print($self->compressed_output);
    $logger->debug("Saved compressed output to $filename");


	$logger->info("Starting checkout of go-svn");

	my $svn = SVN::Client->new;
	$svn->checkout($self->submission_url, $self->checkout_folder,  'HEAD',  0);
	copy $filename, catfile($self->checkout_folder, $self->submission_name);
	$svn->add(catfile($self->checkout_folder, $self->submission_name, 0);
	$svn->commit($self->checkout_folder, 0);

	$logger->info("commited ", $self->submission_name,  " to go-svn");

};

1;    # Magic true value required at end of module

