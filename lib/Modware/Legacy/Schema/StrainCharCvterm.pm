package Modware::Legacy::Schema::StrainCharCvterm;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("strain_char_cvterm");
__PACKAGE__->add_columns(
    "strain_char_cvterm_id",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 11
    },
    "strain_id",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 10
    },
    "cvterm_id",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 10
    },
);
__PACKAGE__->set_primary_key("strain_char_cvterm_id");
__PACKAGE__->add_unique_constraint(
    "u_strain_char_cvterm_id",
    [   "cvterm_id", "cvterm_id", "cvterm_id", "cvterm_id",
        "strain_id", "strain_id", "strain_id", "strain_id",
    ],
);

# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-01-07 10:55:58
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:4dARkVvrQNGdzMx3tVG/eA

# You can replace this text with custom content, and it will be preserved on regeneration
1;
