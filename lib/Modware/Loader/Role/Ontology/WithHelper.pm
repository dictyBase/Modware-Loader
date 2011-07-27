package Modware::Loader::Role::Ontology::WithHelper;

use namespace::autoclean;
use Moose::Role;

has 'parser' => (
    is     => 'rw',
    isa    => 'GOBO::Parsers',
    traits => [qw/NoGetopt/],
);

has 'graph' => (
    is     => 'rw',
    isa    => 'GOBO::Graph',
    traits => [qw/NoGetopt/],
);

has 'namespace' => (
    is     => 'rw',
    isa    => 'Str',
    traits => [qw/NoGetopt/],
);

has '_term_cache' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash NoGetopt/],
    default => sub { {} },
    handles => {
        add_to_term_cache   => 'set',
        clean_term_cache    => 'clear',
        terms_in_cache      => 'count',
        terms_from_cache    => 'keys',
        is_term_in_cache    => 'defined',
        get_term_from_cache => 'get'
    }
);

has '_cvrow_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash NoGetopt/],
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_cvrow    => 'set',
        delete_cvrow => 'delete',
        get_cvrow    => 'get',
        has_cvrow    => 'defined'
    }
);

has '_dbrow_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash NoGetopt/],
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_dbrow    => 'set',
        delete_dbrow => 'delete',
        get_dbrow    => 'get',
        has_dbrow    => 'defined'
    }
);

has '_relation_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash NoGetopt/],
    default => sub { [] },
    lazy    => 1,
    handles => {
        add_relation   => 'set',
        all_relations  => 'values',
        has_relation   => 'defined',
        relation_count => 'count'
    }
);

has '_alt_stack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array NoGetopt/],
    default => sub { [] },
    lazy    => 1,
    handles => {
        add_alt        => 'push',
        all_alts       => 'elements',
        add_alt_header => 'unshift',
        alt_count      => 'count'
    }
);

has '_xref_stack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array NoGetopt/],
    default => sub { [] },
    lazy    => 1,
    handles => {
        add_xref        => 'push',
        all_xrefs       => 'elements',
        add_xref_header => 'unshift',
        xref_count      => 'count'
    }
);

has '_synonym_stack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array NoGetopt/],
    default => sub { [] },
    lazy    => 1,
    handles => {
        add_synonym        => 'push',
        all_synonyms       => 'elements',
        add_synonym_header => 'unshift',
        synonym_count      => 'count'
    }
);

has '_rel_attr_stack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array NoGetopt/],
    default => sub { [] },
    lazy    => 1,
    handles => {
        add_rel_attr        => 'push',
        all_rel_attrs       => 'elements',
        add_rel_attr_header => 'unshift',
        rel_attr_count      => 'count'

    }
);

has 'cvrow' => ( is => 'rw', isa => 'DBIx::Class::Row',  traits => [qw/NoGetopt/] );

has '_cvterm_row_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash NoGetopt/],
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_cvterm_row    => 'set',
        delete_cvterm_row => 'delete',
        get_cvterm_row    => 'get',
        has_cvterm_row    => 'defined'
    }
);

has '_node_row_stack' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    traits  => [qw/Array NoGetopt/],
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_node        => 'push',
        get_all_nodes   => 'elements',
        add_node_header => 'unshift',
        node_count      => 'count'
    }
);

has 'relation_attributes' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub {
        return [qw/cyclic reflexive transitive anonymous/];
    },
    lazy       => 1,
    auto_deref => 1,
    traits     => [qw/NoGetopt/]
);

has 'relation_properties' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub {
        return [qw/domain range/];
    },
    lazy       => 1,
    auto_deref => 1,
    traits     => [qw/NoGetopt/]
);

has 'synonym_scopes' => (
    is      => 'rw',
    isa     => 'ArrayRef',
    default => sub {
        return [qw/EXACT BROAD NARROW RELATED/];
    },
    lazy       => 1,
    auto_deref => 1,
    traits     => [qw/NoGetopt/]
);

has 'term_types' => (
    is         => 'rw',
    isa        => 'ArrayRef',
    lazy       => 1,
    traits     => [qw/NoGetopt/],
    auto_deref => 1,
    default    => sub {
        return [qw/relations terms/];
    }
);

1;
