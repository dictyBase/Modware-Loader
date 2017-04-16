package Modware::Export::Command::stockordersplasmids;

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
        select 
        SO.STOCK_ORDER_ID ORDER_ID, 
        SO.ORDER_DATE,
        PLASMID.ID,
        PLASMID.NAME,
        COLLEAGUE.COLLEAGUE_NO,
        COLLEAGUE.FIRST_NAME,
        COLLEAGUE.LAST_NAME,
        EMAIL.EMAIL
        from CGM_DDB.PLASMID
        JOIN CGM_DDB.STOCK_ITEM_ORDER SIO ON
        (
          PLASMID.ID=SIO.ITEM_ID
          AND
          PLASMID.NAME=SIO.ITEM
        )
        join CGM_DDB.STOCK_ORDER SO on SIO.ORDER_ID=SO.STOCK_ORDER_ID
        left join CGM_DDB.COLLEAGUE on COLLEAGUE.COLLEAGUE_NO=SO.COLLEAGUE_ID
        left join CGM_DDB.COLL_EMAIL COE on COE.COLLEAGUE_NO=COLLEAGUE.COLLEAGUE_NO
        left join CGM_DDB.EMAIL on EMAIL.EMAIL_NO=COE.EMAIL_NO
    }
);


sub execute {
    my ($self) = @_;
    my $dbh    = $self->dbh;
    my $sth    = $dbh->prepare( $self->statement );
    $sth->execute;
    my $output = $self->output_handler;
    my $csv = Text::CSV->new( { auto_diag => 1, binary => 1 } );
    $csv->print( $output, [ "StockOrder_ID", 
                            "OrderDate", 
                            "PlasmidID", 
                            "PlasmidName", 
                            "ColleagueID",
                            "FirstName", 
                            "LastName", 
                            "email" 
                            ] );
    $output->print("\n");

    while   (
        my( $stock_order_id, 
            $order_date, 
            $sc_id, 
            $stock_name, 
            $colleague_no,
            $first_name,
            $last_name,      
            $email
        ) = $sth->fetchrow()
    )
    {
        # Control of required values
        stop_empty($stock_order_id);
        stop_empty($order_date);
        stop_empty($sc_id);
        stop_empty($stock_name);
        # Not required values that might be empty.
        my $colleague_no_in = check_if_empty_col_num($colleague_no);
        my $first_name_in = check_if_empty_name($first_name);
        my $last_name_in = check_if_empty_name($last_name);
        my $emailin = check_if_empty_email($email);
        $csv->print(
            $output,
            [   $stock_order_id, 
                $order_date, 
                $sc_id, 
                $stock_name, 
                $colleague_no_in,
                $first_name_in,
                $last_name_in,      
                $emailin
            ]
        );
        $output->print("\n");
    }
}

sub check_if_empty_email {
    my ($self) = @_;
    my $blank = 'no@email.com';
    if(!(defined $self)) {
        return($blank);
    }
    else{
        return($self);
    }
}

sub check_if_empty_name {
    my ($self) = @_;
    my $blank = 'Anonymous';
    if(!(defined $self)) {
        return($blank);
    }
    else{
        return($self);
    }
}

sub check_if_empty_col_num {
    my ($self) = @_;
    my $blank = 10000001;
    if(!(defined $self)) {
        return($blank);
    }
    else{
        return($self);
    }
}

sub stop_empty {
    my ($self) = @_;
    if(!(defined $self)) {
        die "REQUIRED VALUE IS EMPTY!\n";
    }
}

1;

__END__

=head1 NAME

Modware::Export::Command::stockordersplasmids - Export a csv format of stock center orders of plasmids
