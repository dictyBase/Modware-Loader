package Modware::MOD::Registry;
use namespace::autoclean;
use Moose;

has '_db_map' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub {
        return {
            'DB:GI'      => 'DB:NCBI_gi',
            'GI'         => 'DB:NCBI_gi',
            'protein_id' => 'DB:NCBI_GP'
        };
    },
    handles => {
        'has_alias' => 'defined',
        'get_alias' => 'get'
    }
);

has '_prefix_map' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub {
        return {
            'DB:dictyBase' => 'http://genomes.dictybase.org/id/',
            'DB:NCBI_gi' =>
                'http://www.ncbi.nlm.nih.gov/entrez/viewer.fcgi?val=',
            'DB:NCBI_GP' => 'http://www.ncbi.nlm.nih.gov/protein/'
        };
    },
    handles => { get_url_prefix => 'get', 'has_db' => 'defined' }
);

has '_url_map' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub {
        return {
            'DB:dictyBase' => 'http://genomes.dictybase.org',
            'DB:NCBI_gi'   => 'http://www.ncbi.nlm.nih.gov',
            'DB:NCBI_GP'   => 'http://www.ncbi.nlm.nih.gov'
        };

    },
    handles => { get_url => 'get' }
);

has '_desc_map' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => [qw/Hash/],
    lazy    => 1,
    default => sub {
        return {
            'dictyBase' => 'Dictyostelium genome database',
            'NCBI_GP'   => 'NCBI GenPept',
            'NCBI_gi'   => 'NCBI databases'
        };
    },
    handles => { get_description => 'get' }
);

__PACKAGE__->meta->make_immutable;

1;
