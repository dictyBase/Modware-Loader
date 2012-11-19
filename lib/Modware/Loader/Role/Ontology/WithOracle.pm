package Modware::Loader::Role::Ontology::WithOracle;

# Other modules:
use namespace::autoclean;
use Moose::Role;
use Modware::Loader::Response;

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

sub setup {
    my $self       = shift;
    my $source     = $self->chado->source('Cv::Cvtermsynonym');
    $source->remove_column('synonym');
    $source->add_column(
        'synonym_' => {
            data_type   => 'varchar',
            is_nullable => 0,
            size        => 1024
        }
    );

}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Loader::Role::Chado::BCS::Engine::Oracle

