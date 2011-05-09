package Modware::Load::Command::pub2dicty;
use strict;

# Other modules:
use namespace::autoclean;
use Moose;
use Email::Valid;
use File::Find::Rule;
use File::stat;
use Bio::Biblio::IO;
use Modware::DataSource::Chado;
use Modware::Publication::DictyBase;
use Modware::Publication::Author;
use Try::Tiny;
use Carp;
extends qw/Modware::Load::Command/;
with 'Modware::Role::Command::WithLogger';
with 'Modware::Role::Command::WithHTML';
with 'Modware::Role::Command::WithEmail';

# Module implementation
#

has 'source' => (
    is            => 'rw',
    isa           => 'Str',
    default       => 'PUBMED',
    documentation => 'Primary source of the publication,  default is PUBMED'
);

has 'type' => (
    is      => 'rw',
    isa     => 'Str',
    default => 'journal article',
    documentation =>
        'The type of publication,  default is * journal article *'
);

has '+input' => (
    documentation =>
        'pubmedxml format file,  default is to pick up the latest from data dir,  file name that matches pubmed_[datestring].xml',
    default => sub {
        my $self = shift;
        my @files = map { $_->[1] }
            sort { $b->[0] <=> $a->[0] }
            map { [ stat($_)->mtime, $_ ] }
            File::Find::Rule->file->name(qr/^pubmed\_\d+\.xml$/)
            ->in( $self->data_dir );
        croak "no input file found\n" if !@files;
        $files[0];
    },
    lazy => 1
);

sub execute {
    my $self = shift;
    my $log  = $self->dual_logger;

    Modware::DataSource::Chado->connect(
        dsn      => $self->dsn,
        user     => $self->user,
        password => $self->password,
        attr     => $self->attribute
    );
    my $biblio = Bio::Biblio::IO->new(
        -format => 'pubmedxml',
        -file   => $self->input
    );

    $log->info( 'going to load file ', $self->input );

    my $loaded  = 0;
    my $skipped = 0;
    while ( my $ref = $biblio->next_bibref ) {
        my $pubmed_id = $ref->pmid;
        if ( my $exist
            = Modware::Publication::DictyBase->find_by_pubmed_id($pubmed_id) )
        {
            $log->warn("Publication with $pubmed_id exist");
            $skipped++;
            next;
        }
        my $pub = Modware::Publication::DictyBase->new;
        $pub->pubmed_id($pubmed_id);
        $pub->$_( $self->$_ ) for qw/source type/;
        $pub->$_( $ref->$_ )  for qw/title volume/;
        $pub->year( $ref->date );
        $pub->status( $ref->pubmed_status );
        $pub->issue( $ref->issue )        if $ref->issue;
        $pub->pages( $ref->medline_page ) if $ref->medline_page;
        $pub->abstract( $ref->abstract )  if $ref->abstract;

        if ( my $journal = $ref->journal ) {
            my $abbr = $journal->abbreviation;
            my $name = $journal->name;
            if ( $name and $abbr ) {
                $pub->journal($name);
                $pub->abbreviation($abbr);
            }
            elsif ($name) {
                $pub->journal($name);
                $pub->abbreviation($name);
            }
            elsif ($abbr) {
                $pub->journal($abbr);
                $pub->abbreviation($abbr);
            }
            else {
                $log->warn(
                    "no journal name or abbreviation found for $pubmed_id");
            }
        }

        for my $pub_author ( @{ $ref->authors } ) {
            my $author = Modware::Publication::Author->new;

            $author->last_name( $pub_author->lastname )
                if $pub_author->can('lastname')
                    and $pub_author->lastname;
            $author->initials( $pub_author->initials )
                if $pub_author->can('initials')
                    and $pub_author->initials;
            $author->first_name( $pub_author->forename )
                if $pub_author->can('forename')
                    and $pub_author->forename;
            $author->suffix( $pub_author->suffix )
                if $pub_author->can('suffix')
                    and $pub_author->suffix;

            if ( $author->has_last_name or $author->has_given_name ) {
                $pub->add_author($author);
            }
        }

        try {
            my $new_pub = $pub->create;
            $self->add_publication($new_pub);
            $loaded++;
            $log->info("Loaded $pubmed_id");
        }
        catch {
            $log->fatal("Could not load entry with pubmed id $pubmed_id\n$_");
        };
    }
    $log->info("Loaded: $loaded\tSkipped: $skipped");
    $self->subject('Pubmed loader robot');    # -- email subject
}

1;    # Magic true value required at end of module

__END__

=head1 NAME

Load pubmed records in dicty chado database

