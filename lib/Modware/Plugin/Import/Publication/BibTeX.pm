package Modware::Plugin::Import::Publication::BibTeX;
use Moose::Role;
use feature qw/say/;

sub parse_uniquename {
    my ( $self, $entry ) = @_;
    if ( $entry->has('pmid') ) {
        return $entry->field('pmid');
    }
    if ( $entry->has('id') ) {
        my $id = $entry->field('id');
        if ( $id =~ /^PUB/ ) {
            $id =~ s/PUB//;
        }
        return $id;
    }
}

sub parse_pub_source {
    my ($self, $entry) = @_;
    if ( $entry->has('pmid') ) {
        return 'PubMed';
    }
    my $key = $entry->key;
    my $id  = $entry->field('id');
    if ( $key =~ /^(\w+)($id)/ ) {
        my $source = $1;
        return uc $source;
    }
}

sub parse_pub_type {
    my ( $self, $entry ) = @_;
    if ( $entry->has('status') ) {
        return 'journal_article';
    }
    return 'unpublished';
}

1;
