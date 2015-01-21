package Modware::Load::Command::gff3tochado;
use strict;
use namespace::autoclean;
use Moose;
use SQL::Library;
use Module::Load;
use File::ShareDir qw/module_dir module_file/;
use Modware::Spec::GFF3::Synonym;
use Modware::Spec::GFF3::Analysis;
use Bio::GFF3::LowLevel qw/gff3_parse_feature gff3_parse_directive/;
use Bio::SeqIO;
use feature qw/say/;
extends qw/Modware::Load::Chado/;
with 'MooseX::Object::Pluggable';

has '+input' => (
    documentation => 'Name of the GFF3 file',
    required      => 1
);
has '+input_handler' => ( traits => [qw/NoGetopt/] );
has 'dry_run' => (
    is            => 'rw',
    isa           => 'Bool',
    lazy          => 1,
    default       => 0,
    documentation => 'Dry run do not save anything in database'
);

has 'pg_schema' => (
    is      => 'rw',
    isa     => 'Str',
    trigger => sub {
        my ( $self, $name ) = @_;
        $self->add_connect_hook("SET SCHEMA '$name'");
    },
    documentation =>
        'Name of postgresql schema where the ontology will be loaded, default is public, obviously ignored for other backend'
);

has 'sqllib' => (
    is        => 'rw',
    isa       => 'SQL::Library',
    predicate => 'has_sqllib',
    documentation =>
        'Path to sql library in INI format, by default picked up from the shared lib folder. Mostly a developer option.'
);

has 'sqlmanager' => (
    is      => 'rw',
    isa     => 'SQL::Library',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    default => sub {
        my ($self) = @_;
        my $sqlmanager;
        if ( $self->has_sqllib ) {
            $sqlmanager = SQL::Library->new( { lib => $self->sqllib } );
        }
        else {
            $sqlmanager = SQL::Library->new(
                {   lib => module_file(
                        'Modware::Loader',
                        lc( $self->schema->storage->sqlt_type ) . '_gff3.lib'
                    )
                }
            );
        }
        return $sqlmanager;
    }
);

has 'synonym_type' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    default => 'symbol',
    documentation =>
        'The cvterm that will be used to store the value(s) of GFF3 Alias tag. By default, cvterm symbol is used. This cvterm will be used for all Alias'
);

has 'synonym_pub_id' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'A publication id that will be used in conjunction with synonym_cvterm. By default, the loader will create a unique publication record. It will stored under pubplace GFF3-Loader in the pub table'
);

has 'target_type' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'cvterm to use for storing the target feature. By default, *sequence_feature* cvterm will be used. This will be used for GFF3 features with Target attribute. For proper processing of Target attribute all the aligned parts should be grouped by a prent(target_type) feature.'
);

has 'analysis_name' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'Name of the analysis that is used to generate the feature. Use the same default as that of analysis_program. Unless analysis_program is given the name will not be used.'
);

has 'analysis_program' => (
    is  => 'rw',
    isa => 'Str',
    documentation =>
        'Name of program that is run for the analysis. Will only be used for features with a valid score column of GFF3 and when given in combination with analysis_program_version. The default is to concatenate the values of source and type columns. This value has to be set in order to use the analysis_name.'
);

has 'analysis_program_version' => (
    is  => 'rw',
    isa => 'Num',
    documentation =>
        'Version of the program that is used to run the analysis. Will be used for features with a valid score column in GFF3 and when given along with analysis_program option. This value has to be set in order to use the analysis_name. By default version 1.0 will be used.'
);

has 'version_plugin' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
    documentation => 'Flag to activate plugin that adds version to all the loaded features, default is false'
);

has 'plugin_namespace' => (
    is      => 'rw',
    isa     => 'Str',
    lazy    => 1,
    traits  => [qw/NoGetopt/],
    default => 'Modware::Plugin::Create',
);

sub setup_staging_loader {
    my ($self)        = @_;
    my $backend       = ucfirst lc( $self->schema->storage->sqlt_type );
    my $staging_class = 'Modware::Loader::GFF3::Staging::' . $backend;
    load $staging_class;
    my $staging_loader = $staging_class->new(
        schema     => $self->schema,
        sqlmanager => $self->sqlmanager,
        logger     => $self->logger,
        organism   => $self->organism,
    );
    my $synonym_spec = Modware::Spec::GFF3::Synonym->new;
    $synonym_spec->type( $self->synonym_type );
    if ( $self->synonym_pub_id ) {
        $synonym_spec->synonym_pubmed( $self->synonym_pub_id );
    }
    $staging_loader->synonym_spec($synonym_spec);

    $staging_loader->target_type( $self->target_type ) if $self->target_type;

    if ( $self->analysis_program and $self->analysis_program_version ) {
        $staging_loader->analysis_spec(
            Modware::Spec::GFF3::Analysis->new(
                program        => $self->analysis_program,
                programversion => $self->analysis_program_version
            )
        );
        $staging_loader->analysis_spec->name( $self->analysis_name )
            if $self->analysis_name;
    }
    return $staging_loader;
}

sub setup_staging_env {
    my ( $self, $loader ) = @_;
    $loader->initialize;
    $loader->create_tables;
}

sub load_data_in_staging {
    my ( $self, $loader ) = @_;
    my $seqio;
    my $handler = $self->input_handler;
    while ( my $line = $handler->getline ) {
        if ( $line =~ /^#{2,}/ ) {
            my $hashref = gff3_parse_directive($line);
            if ( $hashref->{directive} eq 'FASTA' ) {
                $seqio = Bio::SeqIO->new(
                    -fh     => $handler,
                    -format => 'fasta'
                );
                while ( my $seq = $seqio->next_seq ) {
                    $hashref->{seq_id}   = $seq->id;
                    $hashref->{sequence} = $seq->seq;
                    $loader->add_data($hashref);
                }
            }
        }
        else {
            my $feature_hashref = gff3_parse_feature($line);
            $loader->add_data($feature_hashref);
        }
    }
    $loader->bulk_load;
}

sub setup_chado_loader {
    my ($self)  = @_;
    my $backend = ucfirst lc( $self->schema->storage->sqlt_type );
    my $module  = 'Modware::Loader::GFF3::Chado::' . $backend;
    load $module;
    my $loader = $module->new(
        schema     => $self->schema,
        sqlmanager => $self->sqlmanager,
        logger     => $self->logger
    );
    return $loader;
}

sub load_data_in_chado {
    my ( $self, $loader ) = @_;
    my $result = $loader->bulk_load;
    return $result;
}

sub is_so_loaded {
    my ($self) = @_;
    my $row = $self->schema->resultset('Cv::Cv')->find({name => 'sequence'});
    return 1 if $row;
}

sub execute {
    my ($self) = @_;
    my $logger = $self->logger;
    # check if sequence ontology is loaded
    # if not bail out
    if (!$self->is_so_loaded) {
        $logger->logcroak("please load sequence ontology(SO) before loading the gff3 file");
    }

    my $staging_loader = $self->setup_staging_loader;
    $logger->debug("start loading in staging tables");
    my $guard = $self->schema->txn_scope_guard;
    $self->setup_staging_env($staging_loader);
    $self->load_data_in_staging($staging_loader);

    my $chado_loader = $self->setup_chado_loader;
    $logger->debug("start loading in chado tables");
    my $result = $self->load_data_in_chado($chado_loader);
    $logger->debug("loaded $result->{$_} entries in $_") for keys %$result;
    $logger->info( "loaded GFF3 features from ",
        $self->input, " in chado database" );

    # plugin time
    if ($self->version_plugin) {
        $self->load_plugin('+'.$self->plugin_namespace.'::'.'FeatureVersion');
        $self->add_version($self->schema);
        $logger->debug('added version to loaded features');
    }


    if ( $self->dry_run ) {
        $logger->info("Nothing saved in database");
    }
    else {
        $guard->commit;
    }
}

with 'Modware::Role::Command::WithOrganism';

__PACKAGE__->meta->make_immutable;
1;

__END__

=head1 NAME

Modware::Load::Command::gff3tochado - Load GFF3 file in chado database
 
