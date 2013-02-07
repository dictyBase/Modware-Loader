package Modware::Legacy::Schema::GeneProduct;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("gene_product");
__PACKAGE__->add_columns(
  "gene_product_no",
  { data_type => "NUMBER", default_value => undef, is_nullable => 0, size => 10 },
  "gene_product",
  {
    data_type => "VARCHAR2",
    default_value => undef,
    is_nullable => 0,
    size => 480,
  },
  "date_created",
  {
    data_type => "DATE",
    default_value => "SYSDATE ",
    is_nullable => 0,
    size => 19,
  },
  "created_by",
  {
    data_type => "VARCHAR2",
    default_value => "SUBSTR(USER,1,12) ",
    is_nullable => 0,
    size => 12,
  },
  "is_automated",
  { data_type => "NUMBER", default_value => 0, is_nullable => 1, size => 38 },
);
__PACKAGE__->set_primary_key("gene_product_no");
__PACKAGE__->add_unique_constraint(
  "gene_product_uk",
  ["gene_product", "gene_product", "gene_product", "gene_product"],
);


# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-01-07 11:10:44
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:xS1dcAZTIWhoN+geKMEMkw


# You can replace this text with custom content, and it will be preserved on regeneration
1;
