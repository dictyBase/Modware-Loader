package Modware::Spec::GFF3::Synonym;
use Moose;
use namespace::autoclean;

has [qw/type synonym_pubmed/] => ( is => 'rw', isa => 'Str');


__PACKAGE__->meta->make_immutable;
1;

__END__
