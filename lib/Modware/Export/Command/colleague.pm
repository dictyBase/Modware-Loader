package Modware::Export::Command::colleague;

use strict;
use Moose;
use namespace::autoclean;
use Text::CSV;
use IO::Handle;
use MooseX::Types::Path::Class qw/File/;
extends qw/Modware::Export::Command/;
with 'Modware::Role::Command::WithDBI';
with 'Modware::Role::Command::WithLogger';

has '_collg_rel_sql' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => q{
        SELECT member.email email
        FROM colleague collg1
        JOIN coll_email colle1 on colle1.colleague_no = collg1.colleague_no
        JOIN email head on head.email_no = colle1.email_no
        JOIN pi on collg1.colleague_no = pi.pi_no
        JOIN colleague collg2 ON collg2.colleague_no = pi.colleague_no
        JOIN coll_email colle2 on colle2.colleague_no = collg2.colleague_no
        JOIN email member on member.email_no = colle2.email_no
        WHERE head.email = ?
    }
);

has '_is_collg_pi_sql' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => q{
        SELECT count(*) from pi where pi_no = ?
    }
);

has '_colleague_sql' => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => q{
        SELECT collg.colleague_id, 
            email.email, 
            collg.first_name,
            collg.last_name, collg.suffix,
            collg.profession, coll.job_title,
            collg.institution, collg.address1,
            (
                collg.address2 || ' ' ||
                collg.address3 || ' ' ||
                collg.address4
            ) address2,
            collg.city,
            collg.state,
            collg.region,
            collg.country,
            collg.postal_code zipcode,
            collg.is_subscribed,
            phone.phone_num,
            colleague_remark.remark research_interest
        FROM colleague collg
        JOIN coll_email on coll_email.colleague_no = collg.colleague_no
        JOIN email on email.email_no = coll_email.email_no
        JOIN coll_phone on coll_phone.colleague_no = collg.colleague_no
        JOIN phone on phone.phone_no = coll_phone.phone_no
        JOIN colleague_remark on colleague_remark.colleague_no = collg.colleague_no
    }
);

has 'colleague_rel_output_handler' => (
    is      => 'ro',
    isa     => 'IO::Handle',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return $self->has_colleague_rel_output
            ? $self->output->openw
            : IO::Handle->new_from_fd( fileno(STDOUT), 'w' );
    }
);

has 'colleague-rel-output' => (
    is          => 'rw',
    isa         => File,
    cmd_aliases => 'crel',
    traits      => [qw/Getopt/],
    coerce      => 1,
    predicate   => 'has_colleague_rel_output',
    documentation =>
        'Name of the colleague relations output file,  if absent writes to STDOUT'
);

has 'colleague-output' => (
    is          => 'rw',
    isa         => File,
    cmd_aliases => 'cout',
    traits      => [qw/Getopt/],
    coerce      => 1,
    predicate   => 'has_colleague_output',
    documentation =>
        'Name of the colleague output file,  if absent writes to STDOUT'
);

has 'colleague_output_handler' => (
    is      => 'ro',
    isa     => 'IO::Handle',
    traits  => [qw/NoGetopt/],
    lazy    => 1,
    default => sub {
        my ($self) = @_;
        return $self->has_colleague_output
            ? $self->output->openw
            : IO::Handle->new_from_fd( fileno(STDOUT), 'w' );
    }
);

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;

    # output files
    my $csv = Text::CSV->new( { auto_diag => 1, binary => 1 } )
        or $logger->logdie(
        sprintf( "error in creating csv object for colleague output %s\n",
            Text::CSV->error_diag() )
        );
    my $cout = $self->colleague_output_handler;
    my $rsv = Text::CSV->new( { auto_diag => 1, binary => 1 } )
        or $logger->logdie(
        sprintf(
            "error in creating csv object for colleague relation output %s\n",
            Text::CSV->error_diag() )
        );
    my $rout = $self->colleague_rel_output_handler;

    # database setup
    my $dbh = $self->dbh;
    my $cth = $dbh->prepare( $self->_colleague_sql );
    my $rth = $dbh->prepare( $self->_collg_rel_sql );
    my $pth = $dbh->prepare( $self->_is_collg_pi_sql );
    $csv->print(
        $cout,
        [   "Email", "First name", "Last name", "Suffix", "Profession",
            "Job Title", "Institution", "First address", "Second Address",
            "City",      "State",       "Region",        "
            Country", "Zipcode", "Subscribed", "Phone no", "Resarch interest"
        ]
    );
    $rsv->print( $rout, [ "Group leader email", "Member email" ] );
    $cout->print("\n");
    $rout->print("\n");
    $cth->execute;

    my $count  = 0;
    my $rcount = 0;
COLLEAGUE:
    while ( my $hashref = $cth->fetchrow_hashref('NAME_lc') ) {
        $csv->print(
            $cout,
            [   $hashref->{email},         $hashref->{first_name},
                $hashref->{last_name},     $hashref->{suffix},
                $hashref->{profession},    $hashref->{job_title},
                $hashref->{institution},   $hashref->{address1},
                $hashref->{address2},      $hashref->{city},
                $hashref->{state},         $hashref->{region},
                $hashref->{country},       $hashref->{zipcode},
                $hashref->{is_subscribed}, $hashref->{phone_num},
                $hashref->{research_interest}
            ]
        );
        $cout->print("\n");
        $count++;
        my ($count)
            = $dbh->selectrow_array( $pth, {}, ( $hashref->{colleague_id} ) );
        next COLLEAGUE
            if $count == 0;    # this colleague is not a pi(group leader)

        my @vals = $dbh->selectall_array( $rth, {}, ( $hashref->{email} ) );
        next COLLEAGUE
            if @vals == 0;     # this group leader has no member as colleague
        for my $email (@vals) {
            $rsv->print( $rout, [ $hashref->{email}, $email ] );
            $rout->print("\n");
        }
        $rcount++;
    }
    $logger->info("written $count colleague entries");
    $logger->info("written $rcount colleague relation");
}


1;

__END__

=head1 NAME

Modware::Export::Command::colleague - Export colleagues(users) and colleague relationships
