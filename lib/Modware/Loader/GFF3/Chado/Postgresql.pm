package Modware::Loader::GFF3::Chado::Postgresql;
use namespace::autoclean;
use Moose;

has 'schema' => ( is => 'rw', isa => 'Bio::Chado::Schema' );
has 'logger' => ( is => 'rw', isa => 'Log::Log4perl::Logger' );

sub bulk_load {
    my ($self) = @_;
    my $dbh = $self->schema->storage->dbh;
    my $rowstat;
    $rowstat->{temp_new_feature}
        = $dbh->do( $self->sqlmanager->retr('insert_temp_new_feature_ids') );
    for my $name (
        qw/feature featureloc featureloc_target analysisfeature synonym feature_synonym feature_relationship  dbxref feature_dbxref featureprop/
        )
    {
        my $insert_name = 'insert_new_' . $name;
        $self->logger->info("inserting in $insert_name");
        my $rows = $dbh->do( $self->sqlmanager->retr($insert_name) );
        $rowstat->{ 'new_' . $name } = $rows == 0 ? 0 : $rows;
    }
    return $rowstat;
}

sub alter_tables {

}

sub reset_tables {

}

with 'Modware::Loader::Role::WithChado';
__PACKAGE__->meta->make_immutable;
1;
