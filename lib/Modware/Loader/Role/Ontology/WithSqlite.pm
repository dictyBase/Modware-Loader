package Modware::Loader::Role::Ontology::WithSqlite;

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
            {   synonym => $label,
                type_id => $self->helper->find_or_create_cvterm_id(
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

sub transform_schema { }

sub create_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(
        qq{
	        CREATE TEMPORARY TABLE temp_cvterm (
               name varchar(1024) NOT NULL, 
               accession varchar(1024) NOT NULL, 
               is_obsolete integer NOT NULL DEFAULT 0, 
               is_relationshiptype integer NOT NULL DEFAULT 0, 
               definition text, 
               comment text, 
               cv_id integer NOT NULL, 
               db_id integer NOT NULL
      }
    );
}

sub drop_temp_statements {
    my ( $self, $storage ) = @_;
    $storage->dbh->do(qq{DROP TABLE temp_cvterm });
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Modware::Loader::Role::Chado::BCS::Engine::Oracle

