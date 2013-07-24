package Modware::Export::Command::dictypubannotation;

use strict;
use Moose;
extends qw/Modware::Export::Chado/;
use Text::CSV;
use Modware::Schema::Curation::Result::Curator;
use Modware::Schema::Curation::Result::CuratorFeaturePubprop;
use Bio::Chado::Schema::Result::Sequence::FeaturePubprop;

has '+input'    => ( traits => [qw/NoGetopt/] );
has '+organism' => ( traits => [qw/NoGetopt/] );
has '+species'  => ( traits => [qw/NoGetopt/] );
has '+genus'    => ( traits => [qw/NoGetopt/] );

sub execute {
    my ($self) = @_;
    my $csv = Text::CSV->new( { eol => "\n" } );
    my $schema = $self->schema;
    $schema->register_class( 'Curator',
        'Modware::Schema::Curation::Result::Curator' );
    $schema->register_class( 'CuratorFeaturePubprop',
        'Modware::Schema::Curation::Result::CuratorFeaturePubprop' );
    $schema->class('Sequence::FeaturePubprop')->has_one(
        'curator_feature_pubprop' =>
            'Modware::Schema::Curation::Result::CuratorFeaturePubprop',
        { 'foreign.feature_pubprop_id' => 'self.feature_pubprop_id' }
    );
    $schema->unregister_source('Sequence::FeaturePubprop');
    $schema->register_class( 'Sequence::FeaturePubprop',
        'Bio::Chado::Schema::Result::Sequence::FeaturePubprop' );

    my $rs = $schema->resultset('Sequence::FeaturePub')->search(
        {},
        {   'join' => [ { 'feature' => 'dbxref' }, 'pub' ],
            'prefetch' => 'feature_pubprops',
            '+select'  => [ 'dbxref.accession', 'pub.uniquename' ],
            '+as'      => [ 'accession', 'pubmed' ],
        }
    );

    my $output = $self->output_handler;
    my $count  = 0;
    while ( my $row = $rs->next ) {
        my $anno;
        my @pubprops = $row->feature_pubprops;
        if (@pubprops) {

    #get curator name, assuming all the pubprops are annotated by same curator
            my @cfp;
            for my $prop (@pubprops) {
                my $cfp_row = $prop->curator_feature_pubprop;
                if ($cfp_row) {
                    push @cfp,
                          $cfp_row->curator->initials . ':'
                        . $cfp_row->timecreated . ':'
                        . $prop->type->name;
                }
                else {
                    push @cfp, $prop->type->name;
                    $self->logger->warn(
                        sprintf(
                            "pub:%s\tfeature:%s\tkeyword:%s\thave no curator assignment",
                            $row->get_column('pubmed'),
                            $row->get_column('accession'),
                            $prop->type->name
                        )
                    );
                }
            }
            $csv->print(
                $output,
                [   $row->get_column('pubmed'),
                    $row->get_column('accession'),
                    @cfp
                ]
            );
        }
        else {
            $csv->print( $output,
                [ $row->get_column('pubmed'), $row->get_column('accession') ]
            );
        }

    }
    $output->close;
}

__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Modware::Export::Command::dictypubannotation - Export literature annotations at dictybase
