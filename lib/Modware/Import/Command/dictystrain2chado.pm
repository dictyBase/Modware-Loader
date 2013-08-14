
use strict;

package Modware::Import::Command::dictystrain2chado;

use Moose;
use namespace::autoclean;

extends qw/Modware::Import::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Stock::Import::Strain';

has 'prune' => ( is => 'rw', isa => 'Bool', default => 0 );

sub execute {

    my ($self) = @_;

    my $guard = $self->schema->txn_scope_guard;

    if ( $self->prune ) {
        $self->schema->storage->dbh_do(
            sub {
                my ( $storage, $dbh ) = @_;
                my $sth = $dbh->prepare(qq{DELETE FROM stock});
                $sth->execute;
            }
        );
    }

    my $type_id = $self->schema->resultset('Cv::Cvterm')
        ->search( { name => 'strain' }, {} )->first->cvterm_id;

    my $io = IO::File->new( $self->input, 'r' );
    my $hash;
    while ( my $line = $io->getline ) {
        my @cols = split( /\t/, $line );
        $hash->{uniquename}  = $cols[0] if $cols[0] =~ /^DBS[0-9]{7}/;
        $hash->{name}        = $cols[1];
        $hash->{organism_id} = $self->find_or_create_organism( $cols[2] )
            if $cols[2];
        $hash->{description} = $self->trim( $cols[3] );
        $hash->{type_id}     = $type_id;
        $self->schema->resultset('Stock::Stock')->create($hash);
        print $hash->{uniquename} . "\t"
            . $hash->{organism_id} . "\t"
            . $type_id . "\n";
    }

    $guard->commit;
    $self->schema->storage->disconnect;
}

1;

__END__

=head1 NAME

Modware::Import::Command::dictystrain2chado - Command to import strain data from dicty stock 

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
