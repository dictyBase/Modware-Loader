package Modware::Load::Types;

use MooseX::Types -declare => [qw/DataDir DataFile FileObject Dsn DbObject ResultSet Row/];
use MooseX::Types::Moose qw/Str Int/;
use Path::Class::File;

subtype DataDir,  as Str, where { -d $_ };
subtype DataFile, 
        as Str, 
        where { -f $_ }, 
        message {"File do not exist"};

class_type FileObject, { class => 'Path::Class::File' };
subtype Dsn, as Str, where {/^dbi:(\w+).+$/};

coerce FileObject, from Str, via { Path::Class::File->new($_) };

class_type ResultSet,  { class => 'DBIx::Class::ResultSet' };
class_type Row,  { class => 'DBIx::Class::Row' };
subtype DbObject,  as ResultSet|Row;

1;

