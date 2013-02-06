package Modware::Role::Command::GOA::Dicty::AppendDuplicate;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use File::AtomicWrite;
use YAML qw/Load/;
use feature qw/say/;
use autodie qw/open close/;
use IO::File;

requires 'input';

# Module implementation
#

before 'execute' => sub {
    my ($self) = @_;
    my $logger = $self->logger;
    my $input  = $self->input;
    $logger->logdie("no input found") if !$input;

    my $data = Load(
        do { local ($/); <DATA> }
    );
    my $sections = [ map {$_} keys %$data ];

    my $reader = IO::File->new($input,  'r');
    my $copy_annotations;
GAF:
    while ( my $line = $reader->getline ) {
        last GAF if keys %$data == 0;
        next if $line =~ /^\!/;

        chomp $line;
        my @gaf_line = split /\t/, $line;
        my $mod_id = $gaf_line[1];

        for my $name (@$sections) {
            if ( exists $data->{$name}->{$mod_id} ) {
                delete $data->{$name}->{$mod_id};
                for my $id ( keys %{ $data->{$name} } ) {
                    my @anno_line = @gaf_line;
                    $anno_line[1] = $id;
                    push @$copy_annotations, join( "\t", @anno_line );
                }
                delete $data->{$name};
            }
        }
    }
    $reader->close;

    my $writer = IO::File->new( $input ,  'a');
    $writer->print( join( "\n", @$copy_annotations ),  "\n" );
    $writer->close;
};

1;    # Magic true value required at end of module

__DATA__
actin:
  DDB_G0289553: 1
  DDB_G0288879: 1
  DDB_G0274129: 1
  DDB_G0274599: 1
  DDB_G0274137: 1
  DDB_G0272520: 1
  DDB_G0272248: 1
  DDB_G0274727: 1
  DDB_G0274133: 1
  DDB_G0274285: 1
  DDB_G0274561: 1
  DDB_G0289005: 1
  DDB_G0289663: 1
  DDB_G0274135: 1
  DDB_G0280545: 1
  DDB_G0269234: 1
  DDB_G0274601: 1
