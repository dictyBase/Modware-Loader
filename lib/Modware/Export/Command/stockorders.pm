package Modware::Export::Command::stockorders;

use strict;
use Moose;
use namespace::autoclean;
use Text::CSV;
extends qw/Modware::Export::Command/;
with 'Modware::Role::Command::WithDBI';
with 'Modware::Role::Command::WithIO';

has '+input' => ( traits => [qw/NoGetopt/] );

has 'statement' => (
    is      => 'ro',
    isa     => 'Str',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => q{
        select sorder.stock_order_id order_id, sc.id id, sc.systematic_name stock_name, 
        colleague.first_name, colleague.last_name, colleague.colleague_no,
        sorder.order_date, email.email from cgm_ddb.stock_center sc
        join cgm_ddb.stock_item_order sitem on 
        ( 
            sc.id=sitem.item_id
            AND
            sc.strain_name = sitem.item
        ) 
        join cgm_ddb.stock_order sorder on sorder.stock_order_id=sitem.order_id
        join cgm_ddb.colleague on colleague.colleague_no = sorder.colleague_id
        JOIN cgm_ddb.coll_email colemail ON colemail.colleague_no=colleague.colleague_no
        JOIN cgm_ddb.email ON email.email_no=colemail.email_no
        UNION ALL
        select sorder.stock_order_id order_id, sc.id id, sc.name stock_name, 
        colleague.first_name, colleague.last_name, colleague.colleague_no,
        sorder.order_date, email.email from plasmid sc
        join stock_item_order sitem on 
        (
              sc.name=sitem.item
              AND
              sc.id = sitem.item_id
        )
        join stock_order sorder on sorder.stock_order_id=sitem.order_id
        join colleague on colleague.colleague_no = sorder.colleague_id
        JOIN cgm_ddb.coll_email colemail ON colemail.colleague_no=colleague.colleague_no
        JOIN cgm_ddb.email ON email.email_no=colemail.email_no
    }
);


sub execute {
    my ($self) = @_;
    my $dbh    = $self->dbh;
    my $sth    = $dbh->prepare( $self->statement );
    $sth->execute;
    my $output = $self->output_handler;
    my $csv = Text::CSV->new( { auto_diag => 1, binary => 1 } );
    $csv->print( $output, [ "Stock Order_ID", "StockID",    "StockName", "FirstName",
        "LastName", "Colleague#", "OrderDate", "email" ] );
    $output->print("\n");
    while ( my ($stock_order_id, $sc_id, $stock_name, $first_name,
            $last_name, $colleague_no, $order_date, $email ) = $sth->fetchrow() ) {
        $csv->print(
            $output,
            [   $stock_order_id, $sc_id,        $stock_name, $first_name,
                $last_name,      $colleague_no, $order_date, $email
            ]
        );
        $output->print("\n");
    }
}

1;

__END__

=head1 NAME

Modware::Export::Command::stockorders - Export a csv format of stock center orders (plasmids and strains)
