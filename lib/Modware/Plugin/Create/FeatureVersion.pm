package Modware::Plugin::Create::FeatureVersion;
use Moose::Role;
use Module::Load;
use SQL::Library;
use File::ShareDir qw/module_file/;

sub add_version {
    my ($self)        = @_;
    my $backend       = ucfirst lc( $self->schema->storage->sqlt_type );
    my $version_class = 'Modware::Create::FeatureVersion::' . $backend;
    my $sqlmanager    = SQL::Library->new(
        {   lib => module_file(
                'Modware::Loader',
                lc( $self->schema->storage->sqlt_type )
                    . '_feature_version.lib'
            )
        }
    );
    load $version_class;
    $version_class->new->create( $self->schema, $sqlmanager );
}

1;

__END__

