package ChadoGFF3CmdLine;
use MooX::Types::MooseLike::Base qw/Str Int AnyOf Undef/;
use Test::Roo::Role;
use Test::Chado qw/:manager/;
use feature qw/say/;

has 'input' => (
    is  => 'rw',
    isa => AnyOf [ Str, Undef ]
);
has 'user' => (
    is  => 'rw',
    isa => AnyOf [ Str, Undef ]
);
has 'password' => (
    is  => 'rw',
    isa => AnyOf [ Str, Undef ]
);
has 'dsn' => (
    is  => 'rw',
    isa => Str,
);
has [
    qw/synonym_type target_type analysis_name
        analysis_program analysis_program_version/
    ] => (
    is  => 'rw',
    isa => Str
    );
has 'genus'       => ( is => 'lazy', isa => Str, default => 'Homo' );
has 'species'     => ( is => 'lazy', isa => Str, default => 'sapiens' );
has 'common_name' => ( is => 'lazy', isa => Str, default => 'human' );

1;
