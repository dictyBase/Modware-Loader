
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'Module::Build' => '0.3601'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Loading module and scripts for Chado relational database ',
  'dist_author' => [
    'Siddhartha Basu <biosidd@gmail.com>'
  ],
  'dist_name' => 'Modware-Loader',
  'dist_version' => '0.001',
  'license' => 'perl',
  'module_name' => 'Modware::Loader',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'Email::Sender::Simple' => '0.102370',
    'Email::Simple' => '2.10',
    'Email::Valid' => '0.184',
    'File::Find::Rule' => '0.32',
    'Log::Log4perl' => '1.30',
    'Modware' => '0.001',
    'MooseX::App::Cmd' => '0.06',
    'MooseX::ConfigFromFile' => '0.02',
    'Spreadsheet::WriteExcel' => '2.37'
  },
  'script_files' => []
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
