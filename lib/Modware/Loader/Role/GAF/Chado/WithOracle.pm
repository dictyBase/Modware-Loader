
use strict;

package Modware::Loader::Role::GAF::Chado::WithOracle;

use Moose::Role;
use namespace::autoclean;

sub transform_schema {
    my ($self)   = @_;
    my $schema   = $self->schema;
    my $fcvt_src = $schema->source('Sequence::FeatureCvtermprop');
    $fcvt_src->remove_column('value');
    $fcvt_src->add_column(
        'value' => {
            data_type   => 'clob',
            is_nullable => 1
        }
    );
    my $pub_src = $schema->source('Pub::Pub');
    $pub_src->remove_column('uniquename');
    $pub_src->add_column(
        'uniquename' => {
            data_type   => 'varchar2',
            is_nullable => 0
        }
    );
    my $syn_src = $schema->source('Cv::Cvtermsynonym');
    $syn_src->remove_column('synonym');
    $syn_src->add_column(
        'synonym_' => {
            data_type   => 'varchar2',
            is_nullable => 0
        }
    );
}

1;
