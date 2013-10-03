package Modware::Legacy::Schema::StrainGeneLink;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("strain_gene_link");
__PACKAGE__->add_columns(
    "strain_id",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 126,
    },
    "feature_id",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 126,
    },
);
__PACKAGE__->set_primary_key( "strain_id", "feature_id" );

# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-01-07 10:55:58
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EgIpfPWgCyxGOVRGmlrZuw

# You can replace this text with custom content, and it will be preserved on regeneration
1;
