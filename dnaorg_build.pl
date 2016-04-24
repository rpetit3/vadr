#!/usr/bin/env perl
# EPN, Mon Aug 10 10:39:33 2015 [development began on dnaorg_annotate_genomes.pl]
# EPN, Mon Feb  1 15:07:43 2016 [dnaorg_build.pl split off from dnaorg_annotate_genomes.pl]
#
use strict;
use warnings;
use Getopt::Long;
use Time::HiRes qw(gettimeofday);
use Bio::Easel::MSA;
use Bio::Easel::SqFile;

require "dnaorg.pm"; 
require "epn-options.pm";

#######################################################################################
# What this script does: 
#
# Preliminaries: 
#   - process options
#   - create the output directory
#   - output program banner and open output files
#   - parse the optional input files, if necessary
#   - make sure the required executables are executable
#
# Step 1. Gather and process information on reference genome using Edirect
#
# Step 2. Fetch and process the reference genome sequence
#
# Step 3. Build and calibrate models
#######################################################################################

# hard-coded-paths:
my $inf_exec_dir   = "/usr/local/infernal/1.1.1/bin/";
my $esl_exec_dir   = "/usr/local/infernal/1.1.1/bin/";
#my $esl_fetch_cds  = "/panfs/pan1/dnaorg/programs/esl-fetch-cds.pl";
my $script_rootdir    = "/panfs/pan1/dnaorg/virseqannot/code";
my $esl_fetch_cds     = $script_rootdir . "/esl-fetch-cds/esl-fetch-cds.pl";

#########################################################
# Command line and option processing using epn-options.pm
#
# opt_HH: 2D hash:
#         1D key: option name (e.g. "-h")
#         2D key: string denoting type of information 
#                 (one of "type", "default", "group", "requires", "incompatible", "preamble", "help")
#         value:  string explaining 2D key:
#                 "type":          "boolean", "string", "int" or "real"
#                 "default":       default value for option
#                 "group":         integer denoting group number this option belongs to
#                 "requires":      string of 0 or more other options this option requires to work, each separated by a ','
#                 "incompatiable": string of 0 or more other options this option is incompatible with, each separated by a ','
#                 "preamble":      string describing option for preamble section (beginning of output from script)
#                 "help":          string describing option for help section (printed if -h used)
#                 "setby":         '1' if option set by user, else 'undef'
#                 "value":         value for option, can be undef if default is undef
#
# opt_order_A: array of options in the order they should be processed
# 
# opt_group_desc_H: key: group number (integer), value: description of group for help output
my %opt_HH = ();      
my @opt_order_A = (); 
my %opt_group_desc_H = ();

# Add all options to %opt_HH and @opt_order_A.
# This section needs to be kept in sync (manually) with the &GetOptions call below
$opt_group_desc_H{"1"} = "basic options";
#     option            type       default               group   requires incompat    preamble-output                          help-output    
opt_Add("-h",           "boolean", 0,                        0,    undef, undef,      undef,                                   "display this help",                                  \%opt_HH, \@opt_order_A);
opt_Add("-c",           "boolean", 0,                        1,    undef, undef,      "genome is circular",                    "genome is circular",                                 \%opt_HH, \@opt_order_A);
opt_Add("-d",           "string",  undef,                    1,    undef, undef,      "directory specified as",                "specify output directory is <s1> (created with dnaorg_build.pl -d <s>), not <ref accession>", \%opt_HH, \@opt_order_A);
opt_Add("-f",           "boolean", 0,                        1,    undef, undef,      "forcing directory overwrite",           "force; if dir <reference accession> exists, overwrite it", \%opt_HH, \@opt_order_A);
opt_Add("-v",           "boolean", 0,                        1,    undef, undef,      "be verbose",                            "be verbose; output commands to stdout as they're run", \%opt_HH, \@opt_order_A);
opt_Add("--matpept",    "string",  undef,                    1,    undef, undef,      "using pre-specified mat_peptide info",  "read mat_peptide info in addition to CDS info, file <s> explains CDS:mat_peptide relationships", \%opt_HH, \@opt_order_A);
opt_Add("--nomatpept",  "boolean", 0,                        1,    undef,"--matpept", "ignore mat_peptide annotation",         "ignore mat_peptide information in reference annotation", \%opt_HH, \@opt_order_A);
opt_Add("--keep",       "boolean", 0,                        1,    undef, undef,      "leaving intermediate files on disk",    "do not remove intermediate files, keep them all on disk", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"2"} = "options affecting calibration of models";
#       option       type       default                group  requires incompat  preamble-output                          help-output    
opt_Add("--slow",   "boolean", 0,                     2,    undef, undef,   "running cmcalibrate in slow mode",               "use default cmcalibrate parameters, not parameters optimized for speed", \%opt_HH, \@opt_order_A);
opt_Add("--local",  "boolean", 0,                     2,    undef, undef,   "running cmcalibrate on local machine",           "run cmcalibrate locally, do not submit calibration jobs for each CM to the compute farm", \%opt_HH, \@opt_order_A);
opt_Add("--rammult",   "boolean",   0,                2,    undef, undef,   "for all models, multiply RAM Gb by ncpu for mem_free", "for all models, multiply RAM Gb by ncpu for mem_free", \%opt_HH, \@opt_order_A);
opt_Add("--bigthresh", "integer", "3000",              2,    undef, undef,   "set minimum length for a big model to <n>",      "set minimum length for a big model to <n>", \%opt_HH, \@opt_order_A);
opt_Add("--bigram",    "integer", "8",                2,    undef, undef,   "for big models, set Gb RAM per core for calibration to <n>", "for big models, set Gb RAM per core for calibration to <n>", \%opt_HH, \@opt_order_A);
opt_Add("--biglen",  "real",     "0.16",              2,    undef, undef,   "for big models, set length to search in Mb as <x>", "for big models, set cmcalibrate length to search in Mb as <x>", \%opt_HH, \@opt_order_A);
opt_Add("--bigncpu",  "integer", "8",                 2,    undef, undef,   "for big models, set number of CPUs for calibration to <n>", "for big models, set number of CPUs for calibration to <n>", \%opt_HH, \@opt_order_A);
opt_Add("--bigtailp",  "real",   "0.30",              2,    undef, undef,   "for big models, set --tailp cmcalibrate parameter as <x>", "for big models, set --tailp cmcalibrate parameter as <x>", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"3"} = "optional output files";
#       option       type       default                group  requires incompat  preamble-output                          help-output    
opt_Add("--mdlinfo",    "boolean", 0,                        3,    undef, undef, "output internal model information",     "create file with internal model information",   \%opt_HH, \@opt_order_A);
opt_Add("--ftrinfo",    "boolean", 0,                        3,    undef, undef, "output internal feature information",   "create file with internal feature information", \%opt_HH, \@opt_order_A);

$opt_group_desc_H{"4"} = "options for skipping stages and use files from earlier, identical run, primarily useful for debugging";
#     option               type       default               group   requires    incompat                  preamble-output                                            help-output    
opt_Add("--skipedirect",   "boolean", 0,                       4,   undef,      undef,                    "skip the edirect steps, use existing results",           "skip the edirect steps, use data from an earlier run of the script", \%opt_HH, \@opt_order_A);
opt_Add("--skipfetch",     "boolean", 0,                       4,   undef,      undef,                    "skip the sequence fetching steps, use existing results", "skip the sequence fetching steps, use files from an earlier run of the script", \%opt_HH, \@opt_order_A);
opt_Add("--skipbuild",     "boolean", 0,                       4,   undef,      undef,                    "skip the build/calibrate steps",                         "skip the model building/calibrating, requires --mdlinfo and/or --ftrinfo", \%opt_HH, \@opt_order_A);


# This section needs to be kept in sync (manually) with the opt_Add() section above
my %GetOptions_H = ();
my $usage    = "Usage: dnaorg_build.pl [-options] <reference accession>\n";
my $synopsis = "dnaorg_build.pl :: build homology models for features of a reference sequence";

my $options_okay = 
    &GetOptions('h'            => \$GetOptions_H{"-h"}, 
# basic options
                'c'            => \$GetOptions_H{"-c"},
                'd=s'          => \$GetOptions_H{"-d"},
                'f'            => \$GetOptions_H{"-f"},
                'v'            => \$GetOptions_H{"-v"},
                'matpept=s'    => \$GetOptions_H{"--matpept"},
                'nomatpept'    => \$GetOptions_H{"--nomatpept"},
                'keep'         => \$GetOptions_H{"--keep"},
# calibration related options
                'slow'         => \$GetOptions_H{"--slow"},
                'local'        => \$GetOptions_H{"--local"},
                'rammult'       => \$GetOptions_H{"--rammult"},
                'bigthresh=s'   => \$GetOptions_H{"--bigthresh"},
                'bigram=s'      => \$GetOptions_H{"--bigram"},
                'biglen=s'      => \$GetOptions_H{"--biglen"},
                'bigncpu=s'     => \$GetOptions_H{"--bigncpu"},
                'bigtailp=s'    => \$GetOptions_H{"--bigtailp"},
# options for skipping stages, using earlier results
                'skipedirect'  => \$GetOptions_H{"--skipedirect"},
                'skipfetch'    => \$GetOptions_H{"--skipfetch"},
                'skipbuild'    => \$GetOptions_H{"--skipbuild"},
# optional output files
                'mdlinfo'      => \$GetOptions_H{"--mdlinfo"},
                'ftrinfo'      => \$GetOptions_H{"--ftrinfo"});

my $total_seconds = -1 * secondsSinceEpoch(); # by multiplying by -1, we can just add another secondsSinceEpoch call at end to get total time
my $executable    = $0;
my $date          = scalar localtime();
my $version       = "0.1";
my $releasedate   = "Apr 2016";

# print help and exit if necessary
if((! $options_okay) || ($GetOptions_H{"-h"})) { 
  outputBanner(*STDOUT, $version, $releasedate, $synopsis, $date);
  opt_OutputHelp(*STDOUT, $usage, \%opt_HH, \@opt_order_A, \%opt_group_desc_H);
  if(! $options_okay) { die "ERROR, unrecognized option;"; }
  else                { exit 0; } # -h, exit with 0 status
}

# check that number of command line args is correct
if(scalar(@ARGV) != 1) {   
  print "Incorrect number of command line arguments.\n";
  print $usage;
  print "\nTo see more help on available options, do dnaorg_build.pl -h\n\n";
  exit(1);
}
my ($ref_accn) = (@ARGV);

# set options in opt_HH
opt_SetFromUserHash(\%GetOptions_H, \%opt_HH);

# validate options (check for conflicts)
opt_ValidateSet(\%opt_HH, \@opt_order_A);

# do checks that are too sophisticated for epn-options.pm
if((opt_Get("--skipbuild", \%opt_HH)) && 
   (! (opt_Get("--mdlinfo", \%opt_HH) || opt_Get("--ftrinfo", \%opt_HH)))) { 
  die "ERROR, --skipbuild requires one or both of --mdlinfo or --ftrinfo"; 
}

my $dir        = opt_Get("-d", \%opt_HH);          # this will be undefined unless -d set on cmdline
my $do_matpept = opt_IsOn("--matpept", \%opt_HH);

#############################
# create the output directory
#############################
my $cmd;              # a command to run with runCommand()
my @early_cmd_A = (); # array of commands we run before our log file is opened
# check if the $dir exists, and that it contains the files we need
# check if our output dir $symbol exists
if(! defined $dir) { 
  $dir = $ref_accn;
}
else { 
  if($dir !~ m/\/$/) { $dir =~ s/\/$//; } # remove final '/' if it exists
}
if(-d $dir) { 
  $cmd = "rm -rf $dir";
  if(opt_Get("-f", \%opt_HH)) { runCommand($cmd, opt_Get("-v", \%opt_HH), undef); push(@early_cmd_A, $cmd); }
  else                        { die "ERROR directory named $dir already exists. Remove it, or use -f to overwrite it."; }
}
if(-e $dir) { 
  $cmd = "rm $dir";
  if(opt_Get("-f", \%opt_HH)) { runCommand($cmd, opt_Get("-v", \%opt_HH), undef); push(@early_cmd_A, $cmd); }
  else                        { die "ERROR a file named $dir already exists. Remove it, or use -f to overwrite it."; }
}

# create the dir
$cmd = "mkdir $dir";
runCommand($cmd, opt_Get("-v", \%opt_HH), undef);
push(@early_cmd_A, $cmd);

my $dir_tail = $dir;
$dir_tail =~ s/^.+\///; # remove all but last dir
my $out_root = $dir . "/" . $dir_tail . ".dnaorg_build";

#############################################
# output program banner and open output files
#############################################
# output preamble
my @arg_desc_A = ("reference accession");
my @arg_A      = ($ref_accn);
outputBanner(*STDOUT, $version, $releasedate, $synopsis, $date);
opt_OutputPreamble(*STDOUT, \@arg_desc_A, \@arg_A, \%opt_HH, \@opt_order_A);

# open the log and command files:
# set output file names and file handles, and open those file handles
my %ofile_info_HH = ();  # hash of information on output files we created,
                         # 1D keys: 
                         #  "fullpath":  full path to the file
                         #  "nodirpath": file name, full path minus all directories
                         #  "desc":      short description of the file
                         #  "FH":        file handle to output to for this file, maybe undef
                         # 2D keys:
                         #  "log": log file of what's output to stdout
                         #  "cmd": command file with list of all commands executed

# open the log and command files 
openAndAddFileToOutputInfo(\%ofile_info_HH, "log", $out_root . ".log", 1, "Output printed to screen");
openAndAddFileToOutputInfo(\%ofile_info_HH, "cmd", $out_root . ".cmd", 1, "List of executed commands");
openAndAddFileToOutputInfo(\%ofile_info_HH, "list", $out_root . ".list", 1, "List and description of all output files");
my $log_FH = $ofile_info_HH{"FH"}{"log"};
my $cmd_FH = $ofile_info_HH{"FH"}{"cmd"};
# output files are all open, if we exit after this point, we'll need
# to close these first.

# open optional output files
if(opt_Get("--mdlinfo", \%opt_HH)) { 
  openAndAddFileToOutputInfo(\%ofile_info_HH, "mdlinfo", $out_root . ".mdlinfo", 1, "Model information (created due to --mdlinfo)");
}
if(opt_Get("--ftrinfo", \%opt_HH)) { 
  openAndAddFileToOutputInfo(\%ofile_info_HH, "ftrinfo", $out_root . ".ftrinfo", 1, "Feature information (created due to --ftrinfo)");
}

# now we have the log file open, output the banner there too
outputBanner($log_FH, $version, $releasedate, $synopsis, $date);
opt_OutputPreamble($log_FH, \@arg_desc_A, \@arg_A, \%opt_HH, \@opt_order_A);

# output any commands we already executed to $log_FH
foreach $cmd (@early_cmd_A) { 
  print $cmd_FH $cmd . "\n";
}

########################################
# parse the optional input files, if nec
########################################
# -matpept <f>
my @cds2pmatpept_AA = (); # 1st dim: cds index (-1, off-by-one), 2nd dim: value array of primary matpept indices that comprise this CDS
my @cds2amatpept_AA = (); # 1st dim: cds index (-1, off-by-one), 2nd dim: value array of all     matpept indices that comprise this CDS
if($do_matpept) { 
  parseMatPeptSpecFile(opt_Get("--matpept", \%opt_HH), \@cds2pmatpept_AA, \@cds2amatpept_AA, $ofile_info_HH{"FH"});
}

###################################################
# make sure the required executables are executable
###################################################
my %execs_H = (); # hash with paths to all required executables
$execs_H{"cmbuild"}       = $inf_exec_dir . "cmbuild";
$execs_H{"cmcalibrate"}   = $inf_exec_dir . "cmcalibrate";
$execs_H{"cmfetch"}       = $inf_exec_dir . "cmfetch";
$execs_H{"cmpress"}       = $inf_exec_dir . "cmpress";
$execs_H{"esl-reformat"}  = $esl_exec_dir . "esl-reformat";
$execs_H{"esl_fetch_cds"} = $esl_fetch_cds;
validateExecutableHash(\%execs_H, $ofile_info_HH{"FH"});

###########################################################################
# Step 1. Gather and process information on reference genome using Edirect.
###########################################################################
my $progress_w = 60; # the width of the left hand column in our progress output, hard-coded
my $start_secs = outputProgressPrior("Gathering information on reference using edirect", $progress_w, $log_FH, *STDOUT);

my %cds_tbl_HHA = ();   # CDS data from .cds.tbl file, hash of hashes of arrays, 
                        # 1D: key: accession
                        # 2D: key: column name in gene ftable file
                        # 3D: per-row values for each column
my %mp_tbl_HHA = ();    # mat_peptide data from .matpept.tbl file, hash of hashes of arrays, 
                        # 1D: key: accession
                        # 2D: key: column name in gene ftable file
                        # 3D: per-row values for each column
my %seq_info_HA = ();   # hash of arrays, avlues are arrays [0..$nseq-1];
                        # 1st dim keys are "seq_name", "accn_name", "seq_len", "accn_len".
                        # $seq_info_HA{"accn_name"}[0] is our reference accession
@{$seq_info_HA{"accn_name"}} = ($ref_accn);

# Call the wrapper function that does the following:
#  1) creates the edirect .mat_peptide file, if necessary
#  2) creates the edirect .ftable file
#  3) creates the length file
#  4) parses the edirect .mat_peptide file, if necessary
#  5) parses the edirect .ftable file
#  6) parses the length file
wrapperGetInfoUsingEdirect(undef, $ref_accn, $out_root, \%cds_tbl_HHA, \%mp_tbl_HHA, \%seq_info_HA, \%ofile_info_HH, 
                           \%opt_HH, $ofile_info_HH{"FH"}); # 1st argument is undef because we are only getting info for $ref_accn

if($do_matpept) {  
  # validate the CDS:mat_peptide relationships that we read from the $matpept input file
  matpeptValidateCdsRelationships(\@cds2pmatpept_AA, \%{$cds_tbl_HHA{$ref_accn}}, \%{$mp_tbl_HHA{$ref_accn}}, opt_Get("-c", \%opt_HH), $seq_info_HA{"accn_len"}[0], $ofile_info_HH{"FH"});
}
outputProgressComplete($start_secs, undef, $log_FH, *STDOUT);

#########################################################
# Step 2. Fetch and process the reference genome sequence
##########################################################
$start_secs = outputProgressPrior("Fetching and processing the reference genome", $progress_w, $log_FH, *STDOUT);
my %mdl_info_HA = ();          # hash of arrays, values are arrays [0..$nmdl-1];
                               # see dnaorg.pm::validateModelInfoHashIsComplete() for list of all keys
                               # filled in wrapperFetchAllSequencesAndProcessReferenceSequence()
my %ftr_info_HA = ();          # hash of arrays, values are arrays [0..$nftr-1], 
                               # see dnaorg.pm::validateFeatureInfoHashIsComplete() for list of all keys
                               # filled in wrapperFetchAllSequencesAndProcessReferenceSequence()
my $sqfile = undef;            # pointer to the Bio::Easel::SqFile object we'll open in wrapperFetchAllSequencesAndProcessReferenceSequence()


# Call the wrapper function that does the following:
#   1) fetches the sequences listed in @{$seq_info_HAR->{"accn_name"} into a fasta file 
#      and indexes that fasta file, the reference sequence is $seq_info_HAR->{"accn_name"}[0].
#   2) determines information for each feature (strand, length, coordinates, product) in the reference sequence
#   3) determines type of each reference sequence feature ('cds-mp', 'cds-notmp', or 'mp')
#   4) fetches the reference sequence feature and populates information on the models and features
wrapperFetchAllSequencesAndProcessReferenceSequence(\%execs_H, \$sqfile, $out_root, \%cds_tbl_HHA,
                                                    ($do_matpept) ? \%mp_tbl_HHA      : undef, 
                                                    ($do_matpept) ? \@cds2pmatpept_AA : undef, 
                                                    ($do_matpept) ? \@cds2amatpept_AA : undef, 
                                                    \%mdl_info_HA, \%ftr_info_HA, \%seq_info_HA,
                                                    \%opt_HH, \%ofile_info_HH);

# verify our model and feature info hashes are complete, 
# if validateFeatureInfoHashIsComplete() fails then the program will exit with an error message
my $nftr = validateFeatureInfoHashIsComplete(\%ftr_info_HA, undef, $ofile_info_HH{"FH"}); # nftr: number of features
my $nmdl = validateModelInfoHashIsComplete  (\%mdl_info_HA, undef, $ofile_info_HH{"FH"}); # nmdl: number of homology models

outputProgressComplete($start_secs, undef, $log_FH, *STDOUT);

#dumpInfoHashOfArrays("ftr_info", 0, \%ftr_info_HA, *STDOUT);

####################################
# Step 3. Build and calibrate models 
####################################
my $do_local = opt_Get("--local", \%opt_HH); # are we running calibration locally
if(! opt_Get("--skipbuild", \%opt_HH)) { 
  my $build_str = $do_local ? "Building and calibrating models" : "Building models and submitting calibration jobs to the farm";
  $start_secs = outputProgressPrior($build_str, $progress_w, $log_FH, *STDOUT);
  createCmDb(\%execs_H, $ofile_info_HH{"fullpath"}{"refstk"}, $out_root . ".ref", \@{$mdl_info_HA{"cmname"}}, \%opt_HH, $ofile_info_HH{"FH"});
  if(! $do_local) { 
    for(my $i = 0; $i < $nmdl; $i++) { 
      addClosedFileToOutputInfo(\%ofile_info_HH, "cm$i", "$out_root.$i.cm", 1, 
                                sprintf("CM file #%d, %s (currently calibrating on the farm)", $i+1, $mdl_info_HA{"out_tiny"}[$i]));
      
    }
  }
  else { 
    addClosedFileToOutputInfo(\%ofile_info_HH, "cm", "$out_root.cm", 1, "CM file with all $nmdl models");
  }
  
  outputProgressComplete($start_secs, undef,  $log_FH, *STDOUT);
}

##########
# Conclude
##########
# output optional output files
if(exists $ofile_info_HH{"FH"}{"mdlinfo"}) { 
  dumpInfoHashOfArrays("Model information (%mdl_info_HA)", 0, \%mdl_info_HA, $ofile_info_HH{"FH"}{"mdlinfo"});
}
if(exists $ofile_info_HH{"FH"}{"ftrinfo"}) { 
  dumpInfoHashOfArrays("Feature information (%ftr_info_HA)", 0, \%ftr_info_HA, $ofile_info_HH{"FH"}{"ftrinfo"});
}

# a quick note to the user about what to do next
if(! opt_Get("--skipbuild", \%opt_HH)) { 
  outputString($log_FH, 1, sprintf("#\n"));
  if(! $do_local) { 
    outputString($log_FH, 1, "# When the $nmdl cmcalibrate jobs on the farm finish, you can use dnaorg_annotate.pl\n");
    outputString($log_FH, 1, "# to use them to annotate genomes.\n");
  }
  else { 
    outputString($log_FH, 1, "# You can now use dnaorg_annotate.pl to annotate genomes with the models\n");
    outputString($log_FH, 1, "# you've created here.\n");
  }
  outputString($log_FH, 1, sprintf("#\n"));
}

$total_seconds += secondsSinceEpoch();
outputConclusionAndCloseFiles($total_seconds, $dir, \%ofile_info_HH);
exit 0;


