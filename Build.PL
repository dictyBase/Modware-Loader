
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "Date::Manip" => "6.36",
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Command line apps for Chado relational database ",
  "dist_author" => [
    "Siddhartha Basu <biosidd\@gmail.com>"
  ],
  "dist_name" => "Modware-Loader",
  "dist_version" => "v1.6.0",
  "license" => "perl",
  "module_name" => "Modware::Loader",
  "recommends" => {
    "BibTeX::Parser" => "0.64",
    "BioPortal::WebService" => "v1.0.0",
    "Child" => "0.009",
    "DBD::Oracle" => "1.52",
    "DBD::Pg" => "v2.19.3",
    "Math::Base36" => "0.10",
    "Text::TablularDisplay" => "1.33",
    "XML::LibXML" => "1.70",
    "XML::LibXSLT" => "1.81",
    "XML::Simple" => "2.18"
  },
  "recursive_test_files" => 1,
  "requires" => {
    "Archive::Tar" => "1.92",
    "Bio::Chado::Schema" => "0.20000",
    "Bio::GFF3::LowLevel" => "1.5",
    "Email::Abstract" => "3.006",
    "Email::Address" => "1.900",
    "Email::Sender::Simple" => "0.102370",
    "Email::Simple" => "2.10",
    "Email::Valid" => "0.184",
    "File::Find::Rule" => "0.32",
    "HTML::WikiConverter" => "0.68",
    "HTML::WikiConverter::MediaWiki" => "0.59",
    "Log::Log4perl" => "1.40",
    "MooseX::App::Cmd" => "0.09",
    "MooseX::Attribute::Dependent" => "v1.1.2",
    "MooseX::ConfigFromFile" => "0.10",
    "MooseX::Event" => "v0.2.0",
    "MooseX::Getopt" => "0.56",
    "MooseX::Types::Path::Class" => "0.06",
    "Number::Compare" => "0.03",
    "OBO::Core::Ontology" => "1.40",
    "Regexp::Common" => "2013030901",
    "SQL::Library" => "v0.0.5",
    "Spreadsheet::WriteExcel" => "2.37",
    "Sub::Uplevel" => "0.24",
    "Text::CSV" => "1.32",
    "Tie::Cache" => "0.17",
    "XML::Twig" => "3.44",
    "perl" => "5.010"
  },
  "script_files" => [
    "bin/modware-import",
    "bin/modware-update",
    "bin/modware",
    "bin/modware-transform",
    "bin/modware-export",
    "bin/discoideum-split-canonical.pl",
    "bin/discoideum_tblastn_filter.pl",
    "bin/chado2dicty_gff3_parallel.sh",
    "bin/modware-load",
    "bin/modware-dump",
    "bin/modware-import",
    "bin/modware-update",
    "bin/modware",
    "bin/modware-transform",
    "bin/modware-export",
    "bin/discoideum-split-canonical.pl",
    "bin/discoideum_tblastn_filter.pl",
    "bin/chado2dicty_gff3_parallel.sh",
    "bin/modware-load",
    "bin/modware-dump"
  ],
  "share_dir" => {
    "dist" => "share",
    "module" => {
      "Modware::Loader" => "share"
    }
  },
  "test_requires" => {
    "MooX::Types::MooseLike" => "0.25",
    "Test::Chado" => "v4.0.0",
    "Test::File" => "1.34",
    "Test::Moose::More" => "0.0019",
    "Test::More" => "0.88",
    "Test::Roo" => "1.002",
    "Test::Spec" => "0.46"
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
