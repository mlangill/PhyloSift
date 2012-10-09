#!/usr/bin/env perl
use warnings;
use strict;
use FindBin qw($Bin);
#use lib "$Bin/../lib";
BEGIN { push(@INC, "$Bin/../lib") }

use Getopt::Long;
use Phylosift::Phylosift;
use Carp;
use Phylosift::Settings;
use Phylosift::Utilities qw(debug);
use POSIX;
my $pair             = 0;
my $clean            = 0;
my $continue         = 0;
my $force            = 0;
my $my_debug         = 0;
my $custom;
my $coverage;
my $configuration;
my $help=0;
my $usage = qq~

$0

Usage
==========================================
> phylosift.pl <Mode> <options> <sequence_file>

   sequence_file needs to be in fasta format

> phylosift.pl <Mode> <options> --paired <sequence_file_1> <sequence_file_2>

   sequence_file_1 and _2 need to be in fastq format

Examples
==========================================
> phylosift.pl all --output=my_results illumina_reads.fastq
This command analyzes FastQ format sequence reads and stores the results in a directory called my_results.

> phylosift.pl all --output=genome genome_assembly.fasta
This command will analyze the fasta format genome assembly in genome_assembly.fasta and store the results in a directory called genome.

> phylosift.pl all proteins.fa
This example searches a set of protein sequences. When --output is not given, the results go to a directory called PS_temp/<filename>


Creating a PhyloSift Marker (Does not allow for taxonomic summaries, only searching, aligning and placement steps)
===========================================

> phylosift.pl build_marker <alignment_file> <PD pruning threshold> <optional Acc to NCBI taxonID map>
Example 1:  > phylosift.pl build_marker test.aln 0.01
Example 2:  > phylosift.pl build_marker -f test.aln 0.01
Example 3:  > phylosift.pl build_marker -f test.aln 0.01 file.map

Simulating Reads
===========================================
> phylosift.pl sim --output=<output_path> <genomes_path> <number_of_genomes_to_choose_from> <reads_to_generate>
Example 1: > phylosift.pl sim --output=/home/user/PhyloSift/PS_temp/sim1 genomes 10 100000
   
Index the search databases
============================================
> phylosift index

Mode : Only execute a specific step in the pipeline
  all - execute all the following steps in that order.
  search - only execute the database searches + write candidate files
  align - hmmsearch + hmmalign + trims + coverage filters
  placer - run pplacer on the results from the align step
  summary - run the taxonomy assignment steps
  index - indexes the various databases needed for Rapsearch, Bowtie and Blast
  build_maker - creates a reference package from a multiple alignment file
  sim - Picks random genomes from the concatenated reference tree, 
        knocks the selected genomes out of the marker DB, 
        runs PS on the generated reads from the selected genomes (in different formats).
        evaluates a benchmark on the simulated data.

Options Available at this time :
   -h, --help            Prints the usage section of the README
   -f                    Overrides a previous Phylosift run, if applicable
   --custom <file>       Reads a custom marker list from a file otherwise use all the markers from the markers directory
   --threaded=<number>   Runs Blast and Hmmer using the number of processors specified
                         (DEFAULT : 1)
   --extended            Uses the extended set of markers
   --clean               Cleans the temporary files created by Phylosift (NOT YET IMPLEMENTED)
   --paired              Looks for 2 input files (paired end sequencing) in FastQ format.
                         Reversing the sequences for the second file listed
                         and appending to the corresponding pair from the first file listed.
   --continue            Enables the pipeline to continue to subsequent steps when not using the 'all' mode
   --isolate             Use this mode if you are running data from an Isolate genome
   --simple              Creates a simple taxonomic summary of the output; no Krona output
   --besthit             When there are multiple hits to the same read, keeps only the best hit to that read
   --updated             Use the set of updated markers instead of stock markers
   --marker_url=<url>    Phylosift will use markers available from the url provided
   --coverage=<file>     Provides a contig/scaffold coverage file to Phylosift
   --config=<file>       Provides a custom configuration file to Phylosift
   --output=<dir>        Specifies an output directory other than PStemp
   --debug               Prints debugging messages
   --keep_search         Keeps the blastDir files (Default: Delete the blastDir files after every chunk)
   --chunk=<Number>      Only run a set number of chunks
   --chunk_size=<Number> Run so many sequences per chunk

~;

# set default values
Phylosift::Settings::set_default(parameter=>\$Phylosift::Settings::threads, value=> 1);
Phylosift::Settings::set_default(parameter=>\$Phylosift::Settings::updated, value=> 1);
Phylosift::Settings::set_default(parameter=>\$Phylosift::Settings::force, value=> "0");
Phylosift::Settings::set_default(parameter=>\$Phylosift::Settings::continue, value=> "0");
Phylosift::Settings::set_default(parameter=>\$Phylosift::Settings::custom, value=> "");
Phylosift::Settings::set_default(parameter=>\$Phylosift::Settings::isolate, value=> 0);


my $ps = new Phylosift::Phylosift();
for(my $i=0;$i<scalar(@ARGV);$i++){
	if($ARGV[$i] eq "--config"){
		if(!-e $ARGV[$i+1]){
			croak "Cannot read custom configuration file.\n Aborting\n";
		}else{
			$Phylosift::Settings::custom = $ARGV[$i+1];
		}
	}
}

my @args = @ARGV;
$ps->{"ARGV"}=\@args;	# copy unmodified ARGV here.

GetOptions(
	"output=s"   => \$Phylosift::Settings::file_dir, # directory for output
	"paired"     => \$Phylosift::Settings::paired, # used for paired fastQ input split in 2 different files OR interleaved 
	"custom=s"   => \$Phylosift::Settings::custom, #need a file containing the marker names to use without extensions ** marker names shouldn't contain '_'
	"f"          => \$Phylosift::Settings::force, #overrides a previous run otherwise stop
	"continue"   => \$Phylosift::Settings::continue, #when a mode different than all is used, continue the rest of Phylosift after the section specified by the mode is finished
	"threaded=i" => \$Phylosift::Settings::threads, 
	"simple"     => \$Phylosift::Settings::simple, # generate only a simple text taxonomic summary, no krona, no taxon names in jplace
	"isolate"    => \$Phylosift::Settings::isolate, #use when processing one or more isolate genomes
	"besthit"         => \$Phylosift::Settings::besthit, #should we keep only the best hit when there are multiple?
	"coverage=s"      => \$Phylosift::Settings::coverage, #provides a contig/scaffold coverage file
	"updated_markers=i" => \$Phylosift::Settings::updated, #Indicates if Phylosift uses the updated versions of the Markers.
	"marker_url=s"      => \$Phylosift::Settings::marker_url, # an alternate address to retrieve markers from
	"extended"        => \$Phylosift::Settings::extended, #Should the full extended set of markers be used?
	"config=s"        => \$Phylosift::Settings::configuration, #custom config file
	"remove_dup"      => \$Phylosift::Settings::remove_dup, #removes duplicate taxons when using build_marker
	"keep_search"    => \$Phylosift::Settings::keep_search, #prevents the files from the bastDir from being deleted after each chunk has completed
	"disable_updates" => \$Phylosift::Settings::disable_update_check, # don't check for or download marker updates
	"start_chunk=i"          => \$Phylosift::Settings::start_chunk, #sets the chunk to start with
	"chunks=i"          => \$Phylosift::Settings::chunks, #sets the number of chunks to be run
	"h"               => \$Phylosift::Settings::help, #prints the usage part of the README file
	"help"            => \$Phylosift::Settings::help, #same as -h
	"debug"           => \$Phylosift::Settings::my_debug, #print debugging messages?
) || die $usage;
if ( defined($Phylosift::Settings::help) && $Phylosift::Settings::help != 0 ) {
	print $usage. "\n";
	die "End of Help message\n";
}

$Phylosift::Utilities::debuglevel = $Phylosift::Settings::my_debug;
debug("@ARGV\n");
if ( scalar(@ARGV) < 1 ) {
	croak $usage ;
}elsif ( scalar(@ARGV) == 1 ) {
	croak $usage unless ( $ARGV[0] eq 'index' );
}elsif ( scalar(@ARGV) == 2 ) {
	croak $usage if ($ARGV[0] eq 'index');
	croak $usage unless ( $ARGV[0] && $ARGV[1]  );
}elsif ( scalar(@ARGV) == 3 ) {
	croak $usage unless ( $ARGV[0] && $ARGV[1] && $ARGV[2] );
} else {
	#croak $usage. "\nOR\n" . $usage . "\n";
}
# make sure we're on a 64-bit OS
unless ( (POSIX::uname)[4] =~ /64/ || $^O =~ /arwin/ ) {
	print STDERR (POSIX::uname)[4] . "\n";
	die "Sorry, PhyloSift requires a 64-bit OS to run.\n";
}
debug "PAIR : $pair\n";
if( $ARGV[0] eq 'sim'){
	debug "Running a Simulation\n";
	$ps = $ps->initialize( mode=>$ARGV[0], file_1=>"Sims" );
}else{
	if (exists $ARGV[2] ){
		$ps = $ps->initialize( mode => $ARGV[0], file_1 => $ARGV[1], file_2 => $ARGV[2]) ;
	}else{
		$ps = $ps->initialize( mode => $ARGV[0], file_1 => $ARGV[1]) ;
	}
}
debug "FORCE: " . $Phylosift::Settings::force . "\n";
debug "Continue : " . $Phylosift::Settings::continue . "\n";
$ps->run( force=>$Phylosift::Settings::force, custom=>$Phylosift::Settings::custom, cont=>$Phylosift::Settings::continue );