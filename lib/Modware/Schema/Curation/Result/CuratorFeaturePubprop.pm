package Schema::Curation::Result::CuratorFeaturePubprop;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 NAME

Schema::Curation::Result::CuratorFeaturePubprop

=cut

__PACKAGE__->table("curator_feature_pubprop");

=head1 ACCESSORS

=head2 curator_feature_pubprop_id

  data_type: 'numeric'
  is_nullable: 0
  original: {data_type => "number"}
  size: [10,0]

=head2 curator_id

  data_type: 'numeric'
  is_foreign_key: 1
  is_nullable: 0
  original: {data_type => "number"}
  size: [10,0]

=head2 feature_pubprop_id

  data_type: 'numeric'
  is_foreign_key: 1
  is_nullable: 0
  original: {data_type => "number"}
  size: [10,0]

=head2 timecreated

  data_type: 'datetime'
  default_value: current_timestamp
  is_nullable: 0
  original: {data_type => "date",default_value => \"sysdate"}

=cut

__PACKAGE__->add_columns(
    "curator_feature_pubprop_id",
    {   data_type   => "numeric",
        is_nullable => 0,
        original    => { data_type => "number" },
        size        => [ 10, 0 ],
    },
    "curator_id",
    {   data_type      => "numeric",
        is_foreign_key => 1,
        is_nullable    => 0,
        original       => { data_type => "number" },
        size           => [ 10, 0 ],
    },
    "feature_pubprop_id",
    {   data_type      => "numeric",
        is_foreign_key => 1,
        is_nullable    => 0,
        original       => { data_type => "number" },
        size           => [ 10, 0 ],
    },
    "timecreated",
    {   data_type     => "datetime",
        default_value => \"current_timestamp",
        is_nullable   => 0,
        original      => { data_type => "date", default_value => \"sysdate" },
    },
);
__PACKAGE__->set_primary_key("curator_feature_pubprop_id");
__PACKAGE__->add_unique_constraint( "u_curator_feature_pubprop",
    [ "curator_id", "feature_pubprop_id" ],
);

=head1 RELATIONS

=head2 curator

Type: belongs_to

Related object: L<Schema::Curation::Result::Curator>

=cut

__PACKAGE__->belongs_to(
    "curator",
    "Schema::Curation::Result::Curator",
    { curator_id    => "curator_id" },
    { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);
__PACKAGE__->belongs_to(
    "featurepubprop",
    "Sequence::FeaturePubprop",
    { feature_pubprop_id => "feature_pubprop_id" },
    { is_deferrable => 1, on_delete => "CASCADE", on_update => "CASCADE" },
);

# Created by DBIx::Class::Schema::Loader v0.07002 @ 2010-12-20 21:07:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:opXAZVm1CMdF5DFGoR5IkQ

# You can replace this text with custom content, and it will be preserved on regeneration
1;
