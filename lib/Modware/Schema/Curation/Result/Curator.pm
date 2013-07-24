package Modware::Schema::Curation::Result::Curator;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 NAME

Schema::Curation::Result::Curator

=cut

__PACKAGE__->table("curator");

=head1 ACCESSORS

=head2 curator_id

  data_type: 'numeric'
  is_nullable: 0
  original: {data_type => "number"}
  size: [11,0]

=head2 name

  data_type: 'varchar2'
  is_nullable: 1
  size: 255

=cut

__PACKAGE__->add_columns(
    "curator_id",
    {   data_type   => "numeric",
        is_nullable => 0,
        original    => { data_type => "number" },
        size        => [ 11, 0 ],
    },
    "name",
    { data_type => "varchar2", is_nullable => 0, size => 255 },
    "initials",
    { data_type => "varchar2", is_nullable => 1, size => 255 },
    "password",
    { data_type => "varchar2", is_nullable => 0, size => 32 },
);
__PACKAGE__->set_primary_key("curator_id");

=head1 RELATIONS

=head2 curator_feature_pubprops

Type: has_many

Related object: L<Schema::Curation::Result::CuratorFeaturePubprop>

=cut

__PACKAGE__->has_many(
    "curator_feature_pubprops",
    "Schema::Curation::Result::CuratorFeaturePubprop",
    { "foreign.curator_id" => "self.curator_id" },
    { cascade_copy         => 0, cascade_delete => 0 },
);

# Created by DBIx::Class::Schema::Loader v0.07002 @ 2010-12-20 21:07:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:eyUBhv6qzmKisYFzful8Aw

# You can replace this text with custom content, and it will be preserved on regeneration
1;
