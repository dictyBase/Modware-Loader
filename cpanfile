requires 'MooseX::Getopt', '0.56';
requires 'MooseX::App::Cmd', '0.09';
requires 'MooseX::ConfigFromFile', '0.10';
requires 'MooseX::Event';
requires 'MooseX::Types::Path::Class';

requires 'Bio::Chado::Schema', '0.20000';
requires 'Bio::GFF3::LowLevel', '1.5';

requires 'DBD::Oracle', '1.52';
requires 'Math::Base36', '0.10';

requires 'Email::Simple', '2.10';
requires 'Email::Sender::Simple', '0.102370';
requires 'Email::Valid', '0.184';

requires 'Spreadsheet::WriteExcel', '2.37';
requires 'Log::Log4perl', '1.40';
requires 'Tie::Cache', '0.17';
requires 'File::ShareDir';
requires 'Regexp::Common';
requires 'DateTime::Format::Strptime';

on 'test' => sub {
	requires 'Test::Spec', '0.46';
	requires 'Test::File', '1.34';
	requires 'Test::Moose::More', '0.0019';
};
