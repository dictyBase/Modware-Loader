package Modware::Generator::Command::create;

# Other modules:
use namespace::autoclean;
use Moose;
use FindBin qw/$Bin/;
use Path::Class;
use File::Path qw/make_path/;
use String::CamelCase qw/camelize/;
extends qw/Modware::Generator::Command/;

# Module implementation
#
sub execute {
    my ( $self, $opt, $argv ) = @_;
    my $logger = $self->output_logger;

    # make sure proper arguments are given
    $logger->error_die('Need both group[GROUP] and command[COMMAND] names')
        if !@$argv;
    $logger->error_die('Need command[COMMAND] name') if @$argv == 1;

    my $group = camelize $argv->[0];
    my $cmd   = $argv->[1];

    my $basedir = Path::Class::Dir->new($Bin)->parent->subdir('lib')
        ->subdir('Modware');
    $logger->logdie("expected base directory $basedir do not exist")
        if !-e $basedir;

    my $cmddir = $basedir->subdir($group)->subdir('Command');
    make_path $cmddir, { verbose => 1 };

    my $group_file = $basedir->file( $group . '.pm' );
    $logger->logdie("$group_file exists !!! cannot create a new one")
        if -e $group_file;

    my $group_handler = $group_file->openw;
    $group_handler->print("package Modware::$group;\n\n");
    $group_handler->print(<<'GROUP');

 #Other modules
 use Moose;
 use namespace::autoclean;
 extends qw/MooseX::App::Cmd/;

 1;

 __END__

 =head1 NAME

GROUP

    $group_handler->print("Modware::$group - [Base application class]\n");
    $group_handler->close;
    $logger->info("Created $group_file");

    my $cmd_class_file = $basedir->subdir($group)->file('Command.pm');
    $logger->logdie("$cmd_class_file exists !!! cannot create a new one")
        if -e $cmd_class_file;
    my $cmd_class_handler = $cmd_class_file->openw;
    $cmd_class_handler->print(
        "package Modware::" . $group . "::Command;\n\n" );
    $cmd_class_handler->print(<<'CMD_CLASS');

use namespace::autoclean;
use Moose;
extends qw/MooseX::App::Cmd::Command/;


__PACKAGE__->meta->make_immutable;

1;

CMD_CLASS

    $cmd_class_handler->close;
    $logger->info("Created $cmd_class_file");

    my $cmd_file = $cmddir->file( $cmd . '.pm' );
    $logger->logdie("$cmd_file exists cannot create a new one")
        if -e $cmd_file;
    my $cmd_file_handler = $cmd_file->openw;
    $cmd_file_handler->print(
        "package Modware::" . $group . "::Command::$cmd;\n\n" );
    $cmd_file_handler->print("use namespace::autoclean;\nuse Moose;\n");
    $cmd_file_handler->print(
        "extends qw/Modware::" . $group . "::Command/;\n\n" );
    $cmd_file_handler->print(<<'CMD');

sub execute {
  	my ($self) = @_;
}

1;

__END__

CMD

    $cmd_file_handler->close;
    $logger->info("Created $cmd_file");

}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Generator::Command::create - Creates a new skeleton for Modware Command class


