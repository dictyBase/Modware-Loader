package Modware::Create::FeatureVersion::Sqlite;
use Moose;

sub create {
    my ($self, $app, $schema, $sqlmanager) = @_;
    my $dbh = $schema->storage->dbh;
    my $dbrow = $schema->resultset('General::Db')->find_or_new({name => $app->db_name});
    if (!$dbrow->in_storage) {
        $dbrow->url($app->db_url) if $app->db_url;
        $dbrow->urlprefix($app->db_urlprefix) if $app->db_urlprefix;
        $dbrow->insert;
    }
    my $retval = $dbh->do($sqlmanager->retr('insert_new_dbxref_with_version'), {}, $app->db_name);

    my $sth = $dbh->prepare($sqlmanager->retr('select_all_dbxrefs_with_version'));
    $sth->execute($dbrow->db_id);
    while(my ($id, $accession) = $sth->fetchrow_array()) {
        $dbh->do($sqlmanager->retr('update_feature_with_dbxref_id'), {}, $id, $accession);
        my ($feature_id) = $dbh->selectrow_array($sqlmanager->retr('select_feature_id'), {}, $accession);
        $dbh->do($sqlmanager->retr('update_feature_with_uniquename'), {}, $accession, $id, $feature_id);
    }
}

__PACKAGE__->meta->make_immutable;
1;

__END__
