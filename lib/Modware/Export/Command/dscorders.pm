package Modware::Export::Command::dscorders;

use strict;
use Moose;
use namespace::autoclean;
use Text::CSV;
use IO::Handle;
use MooseX::Types::Path::Class qw/File/;
extends qw/Modware::Export::Command/;
with 'Modware::Role::Command::WithDBI';
with 'Modware::Role::Command::WithLogger';

has '+input' => ( traits => [qw/NoGetopt/] );

has '_plasmid_sql' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => q{
        select email.email, plasmid.name, sorder.order_date from plasmid 
        join stock_item_order sitem on plasmid.name=sitem.item
        join stock_order sorder on sorder.stock_order_id=sitem.stock_item_order_id
        join colleague on colleague.colleague_no = sorder.colleague_id
        join coll_email on coll_email.colleague_no = colleague.colleague_no
        join email on email.email_no = coll_email.email_no
        order by sorder.order_date, email.email
    }
);

has '_strain_sql' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1, 
    default => q{
        WITH item AS
      ( SELECT sitem.stock_item_order_id orid, sitem.item_id FROM stock_item_order sitem
      MINUS
      SELECT sitem.stock_item_order_id orid,sitem.item_id
      FROM plasmid sc
      JOIN stock_item_order sitem
      ON sc.name=sitem.item
      )
        select email.email, dbxref.accession strain_id, sorder.order_date from stock_center strain 
            join item on strain.id= item.item_id
            join stock_order sorder on sorder.stock_order_id= item.orid
            join colleague on colleague.colleague_no = sorder.colleague_id
            join coll_email on coll_email.colleague_no = colleague.colleague_no
            join email on email.email_no = coll_email.email_no
            join cgm_chado.dbxref ON dbxref.dbxref_id = strain.dbxref_id
            order by sorder.order_date, email.email
    }
);

has 'strain-output' => (
    is          => 'rw',
    isa         => File,
    traits      => [qw/Getopt/],
    cmd_aliases => 'so',
    coerce      => 1,
    predicate   => 'has_strain_output',
    documentation =>
        'Name of the strain output file,  if absent writes to STDOUT'
);

has 'strain_output_handler' => (
    is      => 'ro',
    isa     => 'IO::Handle',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return $self->has_strain_output
            ? $self->output->openw
            : IO::Handle->new_from_fd( fileno(STDOUT), 'w' );
    }
);

has 'plasmid-output' => (
    is          => 'rw',
    isa         => File,
    traits      => [qw/Getopt/],
    cmd_aliases => 'po',
    coerce      => 1,
    predicate   => 'has_plasmid_output',
    documentation =>
        'Name of the plasmid output file,  if absent writes to STDOUT'
);

has 'plasmid_output_handler' => (
    is      => 'ro',
    isa     => 'IO::Handle',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return $self->has_plasmid_output
            ? $self->output->openw
            : IO::Handle->new_from_fd( fileno(STDOUT), 'w' );
    }
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;
    my $dbh    = $self->dbh;
    my $pth    = $dbh->prepare( $self->_plasmid_sql );
    $pth->execute;
    my $pout = $self->plasmid_output_handler;
    my $csv = Text::CSV->new( { auto_diag => 1, binary => 1 } )
        or $logger->logdie(
        sprintf( "error in creating csv object %s\n",
            Text::CSV->error_diag() )
        );
    $csv->print( $pout, [ "Email", "Name", "Date" ] );
    $pout->print("\n");
    while ( my $hashref = $pth->fetchrow_hashref('NAME_lc') ) {
        $csv->print( $pout,
            [ $hashref->{email}, $hashref->{name}, $hashref->{order_date} ] );
        $pout->print("\n");
    }
    $logger->info("finished writing plasmid orders");

    my $sth    = $dbh->prepare( $self->_strain_sql );
    $sth->execute;
    my $sout = $self->strain_output_handler;
    $csv = Text::CSV->new( { auto_diag => 1, binary => 1 } )
        or $logger->logdie(
        sprintf( "error in creating csv object %s\n",
            Text::CSV->error_diag() )
        );
    $csv->print( $sout, [ "Email", "Strain_id", "Date" ] );
    $sout->print("\n");
    while ( my $hashref = $sth->fetchrow_hashref('NAME_lc') ) {
        $csv->print( $sout,
            [ $hashref->{email}, $hashref->{strain_id}, $hashref->{order_date} ] );
        $sout->print("\n");
    }
    $logger->info("finished writing strain orders");
}

1;

__END__

=head1 NAME

Modware::Export::Command::dscorders - Export stock center orders(plasmid and strains)
