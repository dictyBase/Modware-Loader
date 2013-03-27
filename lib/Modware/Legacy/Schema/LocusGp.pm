package Modware::Legacy::Schema::LocusGp;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("locus_gp");
__PACKAGE__->add_columns(
    "locus_no",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 10
    },
    "gene_product_no",
    {   data_type     => "NUMBER",
        default_value => undef,
        is_nullable   => 0,
        size          => 10
    },
);
__PACKAGE__->set_primary_key( "locus_no", "gene_product_no" );

# Created by DBIx::Class::Schema::Loader v0.04006 @ 2010-01-07 11:10:44
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:p00Suss/vEFbVuxnIDzXLg

__PACKAGE__->belongs_to( 'locus_gene_product', 'Modware::Legacy::Schema::GeneProduct',
    { 'foreign.gene_product_no' => 'self.gene_product_no' } );

# You can replace this text with custom content, and it will be preserved on regeneration
1;
