package Modware::Plugin::Import::Publication::BibTeX;
use Moose::Role;

sub parse_uniquename {
    my ($self,$entry) = @_;
    if ($entry->has('pmid')) {
        return $entry->field('pmid');
    }
    if ($entry->has('id')) {
        return $entry->field('id');
    }
}

sub parse_pub_source {
    if ($entry->has('pmid')) {
        return 'PubMed';
    }
    my $key = $entry->key;
    my $id = $entry->field('id');
    if ($key =~ /^(\w+)($id)/) {
    }
}

sub parse_pub_type {
    my ($self, $entry) = @_;
    if ($entry->has('status')) {
        return 'journal_article';
    }
    return 'unpublished';
}


1;
