package Modware::Transform::Command::interpro2gff3;
use strict;
use warnings;

#!/usr/local/bin/perl

# $Date: 2012-06-13 $
# $Revision: 1.0.0 $

#Other Modules
use namespace::autoclean;
use IO::File;
use Bio::GFF3::LowLevel qw (gff3_format_feature);
use Moose;
extends qw/Modware::Transform::Command/;

    our $VERSION = '1.0.0';

    has 'input' => (
        is => 'ro', 
        isa => "Str", 
        required  => 1,
        documentation => 'Input tab delimited file required'
);
    
    has 'output' => (
        is => 'ro', 
        isa => "Str", 
        default => 'Output.gff3', 
        documentation => 'Default Output file: Output.gff3'
);
    

    sub execute{
        
        my $running_id;
        my $current_id;
        my $data;
        my $self = shift;
        my $input = $self->input;
        my $output = $self->output;
        
    
        #Opening File with IO file handlers to read in a line at a time
        
        my $fh = IO::File->new( $input, 'r' )
        or die "Can't open $input File: $!";
        
        my $fh2 = IO::File->new( $output, 'w' )
        or die "Couldn't open $output file for writing: $!\n";
        
        $fh2->print("##gff-version\t3\n");
        
        
        while ( my $line = $fh->getline )
        {
            chomp($line);
            my @input_gff = split /\t/, $line;
            
            $current_id = $input_gff[0];
            
            if ($running_id)
            {
                if ( $current_id eq $running_id )
                {
                    push @$data, $line;
                                        
                }
                else
                {
                    $self->write_gff3( $data, $fh2 );
                    undef $data;
                    push @$data, $line;
                }
                
            }    #End of Run/Current IF
            else
            {
                push @$data, $line;
            }
            
            $running_id = $current_id;
            
            
            
        }    #End of While
        
        $self->write_gff3( $data, $fh2 );
    
        $fh->close;
        $fh2->close;    
        
        

    
    } #End of Read File Sub




sub write_gff3
{
    my ( $self, $data, $fh2) = @_;    
    
    
    my @start_end;
    my $outstr = q{};
    my $name;
    my $running_id;
    my $current_id;
    my $domain;
    my $i = 0;

    foreach my $line (@$data)
    {
        my @parts;
        my $gff;
        @parts = split /\t/, $line;

        $gff->{seq_id}              = $parts[0];
        $gff->{source}              = $parts[3];
        $gff->{type}                = 'polypeptide';
        $gff->{end}                 = $parts[7];
        $gff->{strand}              = ".";
        $gff->{phase}               = undef;
        $parts[4] =~s/:.*//;
        $gff->{attributes}->{Alias} = $parts[4];

        
        #Replacing 0 with 1 for starts
        if($parts[6] == 0)
        {
            $gff->{start}               = 1;
        }
        else
        {
            $gff->{start}               = $parts[6];
        }
        

        
        #Changing the score to a . instead of a blank
        if ( !$parts[8] )
        {

            $gff->{score} = q{.};
        }
        else
        {
            $gff->{score} = $parts[8];

        }

        #Setting the ID Attribute to items
        $current_id = $parts[3];

        if ($running_id)
        {
            if ( $current_id eq $running_id )
            {
                $i++;
                $gff->{attributes}->{ID} = $parts[0].".".$i;

            }
            else
            {
                $i++;
                $gff->{attributes}->{ID} = $parts[0].".".$i;
            }

        }    #End of Run/Current IF
        else
        {
            $gff->{attributes}->{ID} = $parts[0].".".$i;
        }

        $running_id = $current_id;

        
        #Creating a string for a group of items
        push @start_end, $parts[6], $parts[7];
        $outstr .= gff3_format_feature($gff);
        $name = $parts[0];
    } # END OF For Each Loop
    

    @start_end = sort { $a <=> $b } @start_end;
    
    if($start_end[0] == 0)
    {
        $start_end[0] = 1 }
    else
    {}


    $fh2->print( "##sequence-region $name $start_end[0] $start_end[-1]\n" 
          . $outstr
          . "###\n" );
    

}

__PACKAGE__->meta->make_immutable;

1;    # Magic true value required at end of module

__END__

=head1 NAME
 
Modware::Transform::Command::interpro2gff3 - Converts dictyBase InterPro Download File into GFF3 Format
 
=head1 SYNOPSIS

perl domain2gff3.pl -i input_file.txt -o output_file.gff3

=head1 REQUIRED ARGUMENTS

B<[-i|-input]> - Takes a InterPro Protein Download File.

=head1 OPTIONS

B<[-o|-output]> - Changes the ouput file name from output.gff3 to the name it is assigned.

=head1 DESCRIPTION

InterPro domains of Dictyostelium proteins data is converted into a compliant GFF3 file.  The InterPro domains of Dictyostelium proteins 
data is tab delimited with 13 columns arranged as follows: 
 
'dictyBase ID	CRC64	Length	Database	Domain ID	Domain Name	Start	End	Score	Status	Date	InterPro ID	InterPro Name'.  
 
 This data sequence is parsed and formatted into GFF3 format.

=head1 DIAGNOSTICS

Warnings that can occur with this module are the following:
 
=over

=item *
 
If words are in the columns for B<start> and B<end>, the module will warn that words do not work with the sort function.

=item *
 
If there is no input file, the module will try to run Dd_trial.txt as an input file in the current working directory.

=item *

If a file is loaded that does not follow the data sequence mentioned in the DESCRIPTION, the module will pull the wrong values and error. 
 
=back
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 None.

=head1 DEPENDENCIES
 
Bio::GFF3::LowLevel

=head1 INCOMPATIBILITIES

None.

=head1 BUGS AND LIMITATIONS

Only works with the InterPro domains of Dictyostelium proteins tab delimited file found on dictyBase website.

=head1 AUTHOR
 
I<Isma'il Mitchell> B<Mitchell.Ismail@gmail.com> &
I<Siddhartha Basu>  B<siddhartha-basu@northwestern.edu>
 
=head1 LICENCE AND COPYRIGHT
 
Copyright (c) B<2012>, Northwestern University. All rights reserved.
 
This module is free software; you can redistribute it and/or modify it under the same terms as Perl itself. See L<perlartistic>.

