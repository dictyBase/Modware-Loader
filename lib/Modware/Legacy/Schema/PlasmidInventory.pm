package Modware::Legacy::Schema::PlasmidInventory;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("plasmid_inventory");
__PACKAGE__->add_columns(
    "id",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 126,
    },
    "location",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 300,
    },
    "storage_date",
    {   data_type     => "DATE",
        default_value => undef,
        is_nullable   => 1,
        size          => 19
    },
    "stored_as",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 300,
    },
    "color",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 20,
    },
    "test_date",
    {   data_type     => "DATE",
        default_value => undef,
        is_nullable   => 1,
        size          => 19
    },
    "verification",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 500,
    },
    "other_comments_and_feedback",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 500,
    },
    "plasmid_id",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 126,
    },
    "stored_by",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 0,
        size          => 50,
    },
    "created_by",
    {   data_type     => "VARCHAR2",
        default_value => "SUBSTR(USER,1,20) ",
        is_nullable   => 0,
        size          => 20,
    },
    "date_created",
    {   data_type     => "DATE",
        default_value => "SYSDATE ",
        is_nullable   => 0,
        size          => 19,
    },
    "date_modified",
    {   data_type     => "DATE",
        default_value => undef,
        is_nullable   => 1,
        size          => 19
    },
);
__PACKAGE__->set_primary_key("id");

# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-01-07 10:55:58
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:S7QFHngjuBQ1axMWAFLinw

# You can replace this text with custom content, and it will be preserved on regeneration
1;
