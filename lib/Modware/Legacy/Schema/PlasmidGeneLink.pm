package Modware::Legacy::Schema::PlasmidGeneLink;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("plasmid_gene_link");
__PACKAGE__->add_columns(
    "plasmid_id",
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
__PACKAGE__->set_primary_key( "plasmid_id", "feature_id" );

# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-01-07 10:55:58
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EgIpfPWgCyxGOVRGmlrZuw

# You can replace this text with custom content, and it will be preserved on regeneration
1;
