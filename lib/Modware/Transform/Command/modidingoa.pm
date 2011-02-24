package Modware::Transform::Command::modidingoa;

# Other modules:
use namespace::autoclean;
use Carp;
use Data::Dump qw/pp/;
use Moose;
use Moose::Util qw/ensure_all_roles/;
extends qw/Modware::Transform::Convert/;

has '+input' => ( documentation => 'input GAF file from GOA project' );

has '+location' => ( documentation =>
        'Full url/path to a resource that will be used by the converter for id translation. By default is expect a gp2protein file'
);

has '+converter' => (
    documentation =>
        'The converter resource role to use for id translation,  default is gp2protein',
    default => 'gp2protein'
);

sub execute {
    my ( $self, $opt, $arg ) = @_;
    my $logger = $self->logger;

    $self->load_converter;

    my $converted     = 0;
    my $not_converted = 0;
    my $total         = 0;

    my $input  = $self->input_handler;
    my $output = $self->output_handler;

LINE:
    while ( my $line = $input->getline ) {
        if ( $line =~ /^\!/ ) {    ## -- skip header
            $output->print($line);
            next LINE;
        }
        $total++;
        my @data = split /\t/, $line;
        if ( my $mod_id = $self->convert( $data[1] ) ) {
            $data[1] = $mod_id;
            $output->print( join( "\t", @data ) );
            $converted++;
            next LINE;
        }

        $logger->warn("Unable to convert id $data[1]");
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

Modware::Transform::Command::modidingoa - Convert uniprot to mod identifiers(canonical) present in GOA gaf file





