package Modware::Legacy::Schema::Reference;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("reference");
__PACKAGE__->add_columns(
    "reference_no",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 10
    },
    "ref_source",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 0,
        size          => 40,
    },
    "status",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 0,
        size          => 40,
    },
    "citation",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 0,
        size          => 1500,
    },
    "year",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 1,
        size          => 4
    },
    "pubmed",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 1,
        size          => 10
    },
    "date_published",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 20,
    },
    "date_revised",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 1,
        size          => 8
    },
    "issue",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 40,
    },
    "page",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 40,
    },
    "volume",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 40,
    },
    "title",
    {   data_type     => "VARCHAR2",
        default_value => undef,
        is_nullable   => 1,
        size          => 400,
    },
    "journal_no",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 1,
        size          => 10
    },
    "book_no",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 1,
        size          => 10
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
);
__PACKAGE__->set_primary_key("reference_no");
__PACKAGE__->add_unique_constraint( "ref_citation_uk",
    [ "citation", "citation", "citation", "citation" ],
);
__PACKAGE__->has_many( "abstracts", "MOD::SGD::Abstract",
    { "foreign.reference_no" => "self.reference_no" },
);
__PACKAGE__->has_many( "locus_gene_infos", "MOD::SGD::LocusGeneInfo",
    { "foreign.reference_no" => "self.reference_no" },
);

# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-01-29 16:13:09
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:02KoDqN4U6ozVTGt+BkceQ

# You can replace this text with custom content, and it will be preserved on regeneration
1;
