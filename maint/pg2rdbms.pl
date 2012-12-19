#!/usr/bin/perl -w

use strict;
use feature qw/say/;
use Cwd;
use Pod::Usage;
use Getopt::Long;
use SQL::Translator;
use SQL::Translator::Schema::Constants;
use SQL::Translator::Utils qw(debug header_comment);
use Path::Class;
use List::MoreUtils qw/any/;

use vars qw[ $VERSION $DEBUG $WARN ];

$VERSION = '1.59';
$DEBUG   = 0 unless defined $DEBUG;
$WARN    = 0 unless defined $WARN;

our $max_id_length = 30;
my %global_names;

my $type = 'oracle';
GetOptions( 'h|help' => sub { pod2usage(1); }, 't|type:s' => \$type );
die "no input given\n" if !$ARGV[0];

my $output = Path::Class::File->new( 'chado.' . $type )->openw;
my $trans  = SQL::Translator->new(
    parser            => 'PostgreSQL',
    producer          => normalize_type( lc $type ),
    quote_field_names => 0,
    quote_table_names => 0
) or die SQL::Translator->error;

$trans->filters( \&filter_for_oracle ) if $type =~ /oracle/i;
my $data = $trans->translate( $ARGV[0] ) or die $trans->error;

if ( $type =~ /mysql/i ) {
    $data =~ s/DEFAULT\s+nextval\S+//mg;
    $data =~ s/without time zone//mg;
}

if ( $type =~ /oracle/i ) {
    $data =~ s/DEFAULT\s+nextval\S+//mg;
    $data =~ s/without time zone DEFAULT now\(\) NOT NULL/DEFAULT sysdate/mg;
    $data =~ s/without time zone DEFAULT now\(\)/DEFAULT sysdate/mg;
    $data =~ s/date DEFAULT now\(\) NOT NULL/date DEFAULT sysdate/mg;
    $data =~ s/false NOT NULL/\'0\' NOT NULL/mg;
    $data =~ s/false/\'0\'/mg;
    $data =~ s/true NOT NULL/\'1\' NOT NULL/mg;
    $data =~ s/true/\'0\'/mg;
    $data =~ s/\bsynonym\b/synonym_/mg;
    $data =~ s/comment\b/comment_/mg;
    $data =~ s/phylonode_relationship_subject_id/phylonode_rel_subj_id/mg;
    $data =~ s/feature_relationshipprop_pub_c1/feat_relprop_pub_c1/mg;
    $data =~ s/phylonode_([a-z]+)_phylonode_id_key/phylo_$1_phylo_id_key/mg;
    $data
        =~ s/studyprop_feature_studyprop_id_key/studprop_feat_studprop_id_key/mg;

    #    $data =~ s/ALTER TABLE (.+)\;/ALTER TABLE $1 ON DELETE CASCADE\;/mg;
}

$output->print($data);
$output->close;

sub filter_for_oracle {
    my ($schema) = @_;
    my $nd_geoloc = $schema->get_table('nd_geolocation');
    for my $fname (qw/latitude longitude altitude/) {
        my $field = $nd_geoloc->get_field($fname);
        $field->data_type('float');
        $field->size(63);
    }
    $schema->drop_table( $_, cascade => 1 )
        for qw/gencode gencode_aa gencode_startcodon/;
    for my $table ( $schema->get_tables ) {
        my @fk_constraints
            = grep { $_->type eq 'FOREIGN KEY' } $table->get_constraints;
        if ( @fk_constraints == 2 ) {
            if ( $fk_constraints[0]->equals( $fk_constraints[1], 1, 1 ) ) {
                say 'matched foreign constraint ', $fk_constraints[0]->name;
                if ( $fk_constraints[0]->name =~ /01$/ ) {
                    $table->drop_constraint( $fk_constraints[0] );
                    say 'drop constraint ', $fk_constraints[0]->name;
                }
                else {
                    $table->drop_constraint( $fk_constraints[1] );
                    say 'drop constraint ', $fk_constraints[1]->name;
                }
            }
        }
        else {
            my %to_delete;
        OUTER:
            for my $i ( 0 .. $#fk_constraints - 1 ) {
                next OUTER if exists $to_delete{ $fk_constraints[$i]->name };
            INNER:
                for my $z ( 1 .. $#fk_constraints ) {
                    next INNER
                        if exists $to_delete{ $fk_constraints[$z]->name };
                    if ( $fk_constraints[$i]
                        ->equals( $fk_constraints[$z], 1, 1 ) )
                    {
                        if ( $fk_constraints[$i]->name =~ /01$/ ) {
                            $to_delete{ $fk_constraints[$i]->name } = 1;
                            say 'going to delete ', $fk_constraints[$i]->name;
                            next OUTER;
                        }
                        $to_delete{ $fk_constraints[$z]->name } = 1;
                        say 'going to delete ', $fk_constraints[$z]->name;
                    }
                }
            }
            $table->drop_constraint($_) for keys %to_delete;
        }

        #drop indexes for which a unique constraint already exists
        my %index_map;
        for my $idx ( $table->get_indices ) {
            my ($field) = $idx->fields;
            $index_map{$field} = $idx->name;
        }
        for my $ucons ( grep { $_->type eq 'UNIQUE' }
            $table->get_constraints )
        {
            my ($field) = $ucons->field_names;
            $table->drop_index( $index_map{$field} )
                if exists $index_map{$field};
        }

#for oracle LOB field cannot be index
# so find something which has an index on text field and make that varchar2(4000)
        for my $idx ( $table->get_indices ) {
            for my $field_name ( $idx->fields ) {
                my $field = $table->get_field($field_name);
                if ( $field->data_type eq 'text' ) {
                    $field->data_type('varchar2');
                    $field->size(4000);
                }
            }
        }
    }
}

sub normalize_type {
    my $string = shift;
    $string = ucfirst $string;
    if ( $string !~ /sql$/ ) {
        return $string;
    }
    $string =~ s/^(\w+)sql$/$1SQL/;
    $string;
}

