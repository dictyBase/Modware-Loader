package Modware::Create::FeatureVersion::Postgresql;
use Moose;

sub create {
    my ( $self, $app, $schema, $sqlmanager ) = @_;
    my $dbh   = $schema->storage->dbh;
    my $dbrow = $schema->resultset('General::Db')
        ->find_or_new( { name => $app->db_name } );
    if ( !$dbrow->in_storage ) {
        $dbrow->url( $app->db_url )             if $app->db_url;
        $dbrow->urlprefix( $app->db_urlprefix ) if $app->db_urlprefix;
        $dbrow->insert;
    }
    my $retval
        = $dbh->do( $sqlmanager->retr('insert_new_dbxref_with_version'),
        {}, $app->db_name );
    $dbh->do( $sqlmanager->retr('update_feature_with_dbxref_id'),
        {}, $dbrow->db_id );
}

__PACKAGE__->meta->make_immutable;
1;

__END__
