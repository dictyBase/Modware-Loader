package Modware::Loader::Ontology;

use Moose;
use Try::Tiny;
use Carp;
use namespace::autoclean;

has 'manager' => (
    is  => 'rw',
    isa => 'Modware::Loader::Ontology::Manager'
);

has 'resultset' => (
    is  => 'rw',
    isa => 'Str'
);

sub store_cache {
    my ( $self, $cache ) = @_;
    my $chado = $self->manager->helper->chado;

    my $index;
    try {
        $chado->txn_do(
            sub {
                #$chado->resultset( $self->resultset )->populate($cache);
                for my $i ( 0 .. scalar @$cache - 1 ) {
                    $index = $i;
                    $chado->resultset( $self->resultset )
                        ->create( $cache->[$i] );
                }
            }
        );
    }
    catch {
        warn "error in creating: $_";
        croak Dumper $cache->[$index];
    };
}

sub process_xref_cache {
    my ($self) = @_;
    my $cache;
    my $chado = $self->manager->helper->chado;
ACCESSION:
    for my $acc ( $self->manager->cached_xref_entries ) {
        my $data = $self->manager->get_from_xref_cache($acc);
        my $rs   = $chado->resultset('General::Dbxref')
            ->search( { accession => $acc, db_id => $data->[1] } );
        next ACCESSION if !$rs->count;

        my $cvterm = $chado->resultset('Cv::Cvterm')->find(
            {   name        => $data->[0],
                is_obsolete => 0,
                cv_id       => $self->manager->cv_namespace->cv_id
            }
        );
        next ACCESSION if !$cvterm;
        push @$cache,
            {
            cvterm_id => $cvterm->cvterm_id,
            dbxref_id => $rs->first->dbxref_id
            };

        $self->manager->remove_from_xref_cache($acc);
    }

    $chado->txn_do(
        sub {
            $chado->resultset('Cv::CvtermDbxref')->populate($cache);
        }
    ) if defined $cache;
}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME

