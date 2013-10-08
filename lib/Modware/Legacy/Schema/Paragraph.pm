package Modware::Legacy::Schema::Paragraph;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("paragraph");
__PACKAGE__->add_columns(
    "paragraph_no",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 10
    },
    "date_written",
    {   data_type     => "DATE",
        default_value => "SYSDATE ",
        is_nullable   => 0,
        size          => 19,
    },
    "written_by",
    {   data_type     => "VARCHAR2",
        default_value => "SUBSTR(USER,1,12) ",
        is_nullable   => 0,
        size          => 12,
    },
    "date_created",
    {   data_type     => "DATE",
        default_value => "SYSDATE ",
        is_nullable   => 0,
        size          => 19,
    },
    "created_by",
    {   data_type     => "VARCHAR2",
        default_value => "SUBSTR(USER,1,12) ",
        is_nullable   => 0,
        size          => 12,
    },
    "paragraph_text",
    {   data_type     => "CLOB",
        default_value => undef,
        is_nullable   => 1,
        size          => 2147483647,
    },
);
__PACKAGE__->set_primary_key("paragraph_no");

# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-01-07 10:55:58
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:MHVTy5SpoU4wV55nY1CT7g

# You can replace this text with custom content, and it will be preserved on regeneration
1;
