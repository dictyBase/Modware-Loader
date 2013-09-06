requires "Bio::Chado::Schema" => "0.20000";
requires "Bio::GFF3::LowLevel" => "1.5";
requires "BioPortal::WebService" => "v1.0.0";
requires "File::Find::Rule" => "0.32";
requires "Log::Log4perl" => "1.40";
requires "MooseX::App::Cmd" => "0.09";
requires "MooseX::Attribute::Dependent" => "v1.1.2";
requires "MooseX::ConfigFromFile" => "0.10";
requires "MooseX::Event" => "v0.2.0";
requires "MooseX::Getopt" => "0.56";
requires "MooseX::Types::Path::Class" => "0.06";
requires "Regexp::Common" => "2013030901";
requires "SQL::Library" => "v0.0.5";
requires "Spreadsheet::WriteExcel" => "2.37";
requires "Tie::Cache" => "0.17";
requires "perl" => "5.010";
recommends "BibTeX::Parser" => "0.64";
recommends "Child" => "0.009";
recommends "DBD::Oracle" => "1.52";
recommends "Email::Sender::Simple" => "0.102370";
recommends "Email::Simple" => "2.10";
recommends "Email::Valid" => "0.184";
recommends "Math::Base36" => "0.10";
recommends "Text::CSV" => "1.32";
recommends "Text::TablularDisplay" => "1.33";
recommends "XML::LibXML" => "1.70";
recommends "XML::LibXSLT" => "1.81";
recommends "XML::Simple" => "2.18";

on 'build' => sub {
  requires "Module::Build" => "0.3601";
};

on 'test' => sub {
  requires "Test::Chado" => "v1.2.0";
  requires "Test::File" => "1.34";
  requires "Test::Moose::More" => "0.0019";
  requires "Test::More" => "0.88";
  requires "Test::Spec" => "0.46";
};

on 'configure' => sub {
  requires "Module::Build" => "0.3601";
};

on 'develop' => sub {
  requires "Test::CPAN::Meta" => "0";
  requires "version" => "0.9901";
};
