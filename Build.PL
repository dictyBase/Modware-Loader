
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Command line apps for Chado relational database ",
  "dist_author" => [
    "Siddhartha Basu <biosidd\@gmail.com>"
  ],
  "dist_name" => "Modware-Loader",
  "dist_version" => "1.1.0",
  "license" => "perl",
  "module_name" => "Modware::Loader",
  "recommends" => {
    "BibTeX::Parser" => "0.64",
    "Child" => "0.009",
    "Text::CSV" => "1.32",
    "Text::TablularDisplay" => "1.33",
    "XML::LibXML" => "1.70",
    "XML::LibXSLT" => "1.81",
    "XML::Simple" => "2.18"
  },
  "recursive_test_files" => 1,
  "requires" => {
    "Bio::Chado::Schema" => "0.20000",
    "Bio::GFF3::LowLevel" => "1.5",
    "BioPortal::WebService" => "v1.0.0",
    "DBD::Oracle" => "1.52",
    "Email::Sender::Simple" => "0.102370",
    "Email::Simple" => "2.10",
    "Email::Valid" => "0.184",
    "File::Find::Rule" => "0.32",
    "Log::Log4perl" => "1.40",
    "Math::Base36" => "0.10",
    "MooseX::App::Cmd" => "0.09",
    "MooseX::Attribute::Dependent" => "v1.1.2",
    "MooseX::ConfigFromFile" => "0.10",
    "MooseX::Event" => "v0.2.0",
    "MooseX::Getopt" => "0.56",
    "MooseX::Types::Path::Class" => "0.06",
    "Regexp::Common" => "2013030901",
    "Spreadsheet::WriteExcel" => "2.37",
    "Tie::Cache" => "0.17",
    "perl" => "5.010"
  },
  "script_files" => [
    "bin/modware-update",
    "bin/modware",
    "bin/modware-transform",
    "bin/modware-export",
    "bin/discoideum-split-canonical.pl",
    "bin/discoideum_tblastn_filter.pl",
    "bin/chado2dicty_gff3_parallel.sh",
    "bin/modware-load",
    "bin/modware-update",
    "bin/modware",
    "bin/modware-transform",
    "bin/modware-export",
    "bin/discoideum-split-canonical.pl",
    "bin/discoideum_tblastn_filter.pl",
    "bin/chado2dicty_gff3_parallel.sh",
    "bin/modware-load"
  ],
  "share_dir" => {
    "dist" => "share",
    "module" => {
      "Modware::Loader" => "share"
    }
  },
  "test_requires" => {
    "Test::More" => "0.88"
  }
);


unless ( eval { Module::Build->VERSION(0.4004) } ) {
  my $tr = delete $module_build_args{test_requires};
  my $br = $module_build_args{build_requires};
  for my $mod ( keys %$tr ) {
    if ( exists $br->{$mod} ) {
      $br->{$mod} = $tr->{$mod} if $tr->{$mod} > $br->{$mod};
    }
    else {
      $br->{$mod} = $tr->{$mod};
    }
  }
}

my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
