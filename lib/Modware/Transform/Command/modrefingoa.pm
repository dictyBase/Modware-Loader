package Modware::Transform::Command::modrefingoa;

# Other modules:
use namespace::autoclean;
use Carp;
use Data::Dump qw/pp/;
use Moose;
use Moose::Util qw/ensure_all_roles/;
extends qw/Modware::Transform::Convert/;

has '+input' => ( documentation => 'input GAF file from GOA project' );

has '+location' => ( documentation =>
        'Full url/path to a resource that will be used by the converter for id translation. By default it expects a GO.references file with the default converter'
);

has '+converter' => (
    documentation =>
        'The converter resource role to use for id translation,  default is goref',
    default => 'goref'
);

has 'godb' => (
    is            => 'rw',
    isa           => 'Str',
    default       => 'GO_REF',
    documentation => 'Database abbreviation for GO reference identifiers'
);

sub execute {
    my ( $self, $opt, $arg ) = @_;
    my $logger = $self->logger;
    $self->load_converter;

    my $converted     = 0;
    my $not_converted = 0;
    my $total         = 0;

    my $input    = $self->input_handler;
    my $output   = $self->output_handler;
    my $godb = $self->godb;
    my $goregexp = qr/^$godb/;

LINE:
    while ( my $line = $input->getline ) {
        if ( $line =~ /^\!/ ) {    ## -- skip header
            $output->print($line);
            next LINE;
        }
        $total++;
        my @data = split /\t/, $line;
        my $ref = $data[5];
        if ( $ref =~ /\|/ ) {
            $ref = first {$goregexp} split /\|/, $ref;
            if ( !$ref ) {
                $output->print($line);
                next LINE;
            }
        }
        else {
            if ( $ref !~ $goregexp ) {
                $output->print($line);
                next LINE;
            }
        }
        if ( my $mod_id = $self->convert($ref) ) {
            $data[5] =~ s/$ref/$mod_id/;
            $output->print( join( "\t", @data ) );
            $converted++;
            next LINE;
        }

        $logger->warn("Unable to convert id $data[5]");
        $not_converted++;
    }

    $input->close;
    $output->close;

    $logger->info(
        "total:$total converted:$converted not_converted:$not_converted");

}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Transform::Command::modrefingoa - Convert GO references to mod reference identifiers present in GOA gaf file





