package Modware::DataSource::Chado;

use strict;
use warnings;

use namespace::clean;
use Bio::Chado::Schema;
use MooseX::Singleton;
use MooseX::Params::Validate;

sub connect {
    my $class  = shift;
    my %params = validated_hash(
        \@_,
        dsn      => { isa => 'Str', optional => 1 },
        user     => { isa => 'Str', optional => 1 },
        password => { isa => 'Str', optional => 1 },
        attr     => {
            isa      => 'HashRef',
            optional => 1,
        },
        extra            => { isa => 'HashRef', optional => 1 },
        source_name      => { isa => 'Str',     optional => 1 },
        adapter          => { isa => 'Str',     optional => 1 },
        reader           => { isa => 'Str',     optional => 1 },
        writer           => { isa => 'Str',     optional => 1 },
        reader_namespace => { isa => 'Str',     optional => 1 },
        writer_namespace => { isa => 'Str',     optional => 1 },
        default          => { isa => 'Bool',    optional => 1 },
    );

    for my $args (
        qw/adapter reader writer
        reader_namespace writer_namspace dsn user password attr extra source_name/
        )
    {

        $class->$args( $params{$args} )
            if defined $params{$args};
    }

    $class->default_source( $params{source_name} )
        if defined $params{default};

    $class->handler_stack if !$class->has_handler_stack;

}

has [qw/dsn user password/] => ( is => 'rw', isa => 'Str' );

has 'attr' => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { { AutoCommit => 1 } },
    lazy    => 1
);

has 'extra' => (
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
    lazy    => 1
);

has 'source_name' => (
    is  => 'rw',
    isa => 'Str',
);

after 'source_name' => sub {
    my ( $class, $source_name ) = @_;
    $class->add_repository( $source_name, $class->adapter );
    $class->add_reader_source( $source_name, $class->reader );
    $class->add_writer_source( $source_name, $class->writer );
    if ( !$class->has_source($source_name) ) {

        my $handler = Bio::Chado::Schema->connect(
            $class->dsn,  $class->user, $class->password,
            $class->attr, $class->extra
        );
        $class->register_handler( $source_name, $handler );
    }
};

has 'default_source' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'gmod'
);

has 'handler_stack' => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    handles => {
        get_handler_by_source_name => 'get',
        register_handler           => 'set',
        delete_handler             => 'delete',
        has_source                 => 'defined',
        sources                    => 'keys'
    },
    lazy_build => 1
);

sub _build_handler_stack {
    my $class  = shift;
    my $source = $class->default_source;
    return {
        $source => Bio::Chado::Schema->connect(
            $class->dsn,  $class->user, $class->password,
            $class->attr, $class->extra
        ),
        'fallback' => Bio::Chado::Schema->connect(
            $class->dsn,  $class->user, $class->password,
            $class->attr, $class->extra
        )
    };
}

has [qw/reader writer adapter/] => (
    is      => 'rw',
    isa     => 'Str',
    default => 'bcs',
    lazy    => 1
);

after 'adapter' => sub {
    my ( $self, $name ) = @_;
    return if !$name;
    $self->reader($name);
    $self->writer($name);
};

has 'reader_namespace' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'Modware::Chado::Reader'
);

has 'writer_namespace' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'Modware::Chado::Writer'
);

has 'reader_source_name_stack' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub { {} },
    handles => {
        add_reader_source                => 'set',
        reader_source_name_by_repository => 'get',
        delete_reader_source_name        => 'delete'
    }
);

has 'writer_source_name_stack' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_writer_source                => 'set',
        writer_source_name_by_repository => 'get',
        delete_writer_source_name        => 'delete'
    }
);

has 'source_name_stack' => (
    traits  => ['Hash'],
    is      => 'rw',
    isa     => 'HashRef',
    default => sub { {} },
    lazy    => 1,
    handles => {
        add_repository          => 'set',
        get_adapter_source_name => 'get',
        delete_repository       => 'delete'
    }
);

sub handler {
    my ( $class, $source_name ) = @_;
    my $handler = $class->get_handler_by_source_name(
        $source_name ? $source_name : $class->default_source );
    $handler;

}

1;
__END__

=head1 NAME

Modware - A GMOD L<http://gmod.org> middleware toolkit for Chado L<http://gmod.org/wiki/Chado> relational database.

=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 AUTHOR

Siddhartha Basu E<lt>biosidd.basu@gmail.comE<gt>

Yulia Bushmanova E<lt>y-bushmanova@northwestern.eduE<gt>

=head1 SEE ALSO

L<http://gmod.org/wiki/Modware>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
