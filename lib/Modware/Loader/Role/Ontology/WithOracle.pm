package Modware::Loader::Role::Ontology::WithOracle;

# Other modules:
use namespace::autoclean;
use Moose::Role;

# Module implementation
#

sub handle_synonyms {
    my ($self) = @_;
    my $node = $self->node;
    return if !$node->synonyms;
    my %uniq_syns = map { $_->label => $_->scope } @{ $node->synonyms };
    for my $label ( keys %uniq_syns ) {
        $self->add_to_insert_cvtermsynonyms(
            {   'synonym_' => $label,
                type_id    => $self->helper->find_or_create_cvterm_id(
                    cvterm => $uniq_syns{$label},
                    cv     => 'synonym_type',
                    dbxref => $uniq_syns{$label},
                    db     => 'internal'
                )
            }
        );
    }
    return Modware::Loader::Response->new(
        is_success => 1,
        message    => 'Loaded all synonyms for ' . $node->id
    );
}

sub transform_schema {
    my ($self) = @_;
    my $schema = $self->schema;
    my $source = $self->schema->source('Cv::Cvtermsynonym');
    $source->remove_column('synonym');
    $source->add_column(
        'synonym_' => {
            data_type   => 'varchar',
            is_nullable => 0,
            size        => 1024
        }
    );
    my @sources = (
        'Cv::Cvprop',     'Cv::Cvtermprop',
        'Cv::Dbxrefprop', 'Sequence::Featureprop',
        'Sequence::FeatureCvtermprop'
    );
    for my $name (@sources) {
        my $result_source = $schema->source($name);
        next if !$result_source->has_column('value');
        $result_source->remove_column('value');
        $result_source->add_column(
            'value' => {
                data_type   => 'clob',
                is_nullable => 1
            }
        );
    }
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Loader::Role::Chado::BCS::Engine::Oracle

