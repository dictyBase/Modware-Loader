package Modware::Create::FeatureVersion::Sqlite;
use Moose;

sub create {
    my ($self, $schema, $sqlmanager) = @_;
    my $dbh = $schema->storage->dbh;
    $dbh->do($sqlmanager->retr('insert_new_dbxref_with_version'));

    my $sth = $dbh->prepare($sqlmanager->retr('select_all_dbxrefs_with_version'));
    $sth->execute();
    while(my ($id, $accession) = $sth->fetch) {
        $dbh->do($sqlmanager->retr('update_feature_with_dbxref_id'), {}, $id, $accession);
        my ($feature_id) = $dbh->selectrow_array($sqlmanager->retr('select_feature_id'), {}, $accession);
        $dbh->do($sqlmanager->retr('update_feature_with_uniquename'), {}, $accession, $feature_id);
    }
}

__PACKAGE__->meta->make_immutable;
1;

__END__
