# bulkrights.pl

#   Automatically backup and remove TRUSTEE rights from NSS volumes
#   on NetWare based on the output for Quest NDS Migrator Tool.  

#   Copyright (C) 2011 Ryan Kather

#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.

#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.

#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Requires: 	Perl::Net::SMTP
# 		Perl::IO::File
#		Perl::Sys::Hostname

# Written By: Ryan Kather

#---------------------------------------
# MAIN ROUTINE
#---------------------------------------

# Use Strict Processing Mode and Warnings for Better Code
use strict;
use warnings;

# Perl Library Includes
use IO::File; # File IO Handling Library
use Net::SMTP; #SMTP Mail Library
use Sys::Hostname; # System Hostname Library

# System Variables
my $host=hostname; # System Hostname
my $nlm="TRUSTEE.NLM"; # TRUSTEE Rights Management Utility
my @userpaths; # User Home Directory Paths Array
my @volumes; # Server Volumes Array

# Editable Configuration Settings
my $datadir="./"; #Trustee Results Data Directory
my $fullbackup="trustee.txt"; #Full Trustee Backup Filename
my $newrights="newtrustee.txt"; # New Trustee Rights Structure
my $postprocess="newtrusts.csv"; #Post Migration Trustee Backup
my $recipient='someuser@example.com'; # Processing Results Recipient
my $relay="smtpserver.example.com"; # SMTP Relay Hostname or IP Address
my $sender=$host.'@example.com'; # SMTP Sender Address
my $timeout=3600; # Maximum Time to Wait for System Commands
my $treename="NDSTREE"; # Novell Tree Name for Regex on Quest Input
my $usermap="user.map"; #User Input File for Home Mappings

# Set up the parameters for our system commands
my @backupcmd=($nlm, "/ETI", "save", "ALL");
my @removecmd=($nlm, "remove");

#---------------------------------------
# CONFIGURATION END -- DO NOT EDIT
#---------------------------------------

# Note Final Array Element Numbers
my $backlast=$#backupcmd;
my $removelast=$#removecmd;

# Parse Server Volumes into Array and Display Output
@volumes=get_volumes();
print "Found the Following Volumes:\n\n\t";
print join "\n\t",@volumes;
print "\n\n";

# Cleanup Leftover Files from Previous Run if Present
clean_files($datadir.$fullbackup);
clean_files($datadir.$postprocess);

# Retrieve Full Backup of System Trustees
system("load @backupcmd $datadir$fullbackup");
sleep(2); # Delay Processing 2 Seconds for NLM Load
wait_for_nlm();

# Parse Input CSV of Migrating Folders
@userpaths=parse_csv($datadir.$usermap);

# Create New Rights Structure 
new_rights();

# Process New Rights Structure

# Retrieve Post Processing Rights Backup
system("load @backupcmd $datadir$postprocess");
sleep(2); # Delay Proessing 2 Seconds for NLM Load
wait_for_nlm();

# Email Success Notification
mail_results($recipient,$relay,$sender);

###### Subroutines and functions ######

#------------------------------(  clean_files  )------------------------#
#  FUNCTION:	clean_files						#
#									#
#  PURPOSE:	Cleanup Rights Files and Bits this Program May Leave	#
#-----------------------------------------------------------------------#
sub clean_files {
        my $leftover=$_[0]; # File with Full Path to be Cleaned

	# Delete Any Leftover File Present Before Posting New Files
	print "Scanning for existing Trustee CSV files in $datadir\n";
	if (-e $leftover) {
		print "Unlinking $leftover.\n";
		unlink(glob("$leftover")) || 
			die "Can't Delete $leftover: $!";
	}
}

#-------------------------(  get_module_status  )-----------------------#
#  FUNCTION:	get_modules_status					#
#									#
#  PURPOSE:	heck whether a nlm is loaded. Returns 0 if not running, #
#		>=1 otherwise.  Relies on NRM XML filesSlurp file for 	#
#		data into array and close file handle.  		#
#									#
#  ARGS:	$nlm - Case Sensitive Name of NLM to Test For		#
#									#
#  RETURNS:	$COUNT - Number of instances found (zero if not found)	#
#-----------------------------------------------------------------------#
sub get_module_status {  
	my $COUNT=0;
	my @modules;
   
	# The NRM XML file that keeps a note of which modules are loaded
	my $nrm_file="_admin:/Novell/NRM/NRMModules.xml";

	open(NRMFILE,$nrm_file) ||
			die "Unable to open $nrm_file. Is NSS loaded?";
		@modules=<NRMFILE>;
	close(NRMFILE);
	
	foreach(@modules) {
		if (/$nlm/) {
			++$COUNT;
      		}	
   	}
	return $COUNT;
}

#----------------------------(  get_volumes  )--------------------------#
#  FUNCTION:    get_volumes						#
#                                                                       #
#  PURPOSE:     Determine which volumes are present on a NetWare server,#
#		but only after discounting special volumes (ADMIN, SYS,	#
#		SNAPSHOT).  						#
#                                                                       #
#  RETURNS:     @vol_names - Array of Discovered Volume Names		#
#-----------------------------------------------------------------------#
sub get_volumes {
	my $ending_value; # Array Length Notation
	my $i=0; # Initialize Array Counter
	my @vol_names; # Volume Details Array

	# Open Volumes XML Listing
	opendir(VOLDIR,"_admin:/Volumes/") ||
		die "Could not open NSS Management file: $!";
	
	# Initialize Volumes into Array
	@vol_names=readdir(VOLDIR) ||
		die "Could not read volumes file: $!";
	
	# Close Volume File when finished Parsing
	closedir(VOLDIR);
	
	# Read the Array Length as Integer
	$ending_value=$#vol_names;
	
	# Restrict the Array Contents to Real Volumes Only
	while ($i < $ending_value) {
		if ((($vol_names[$i]) eq "SYS") ||
			(($vol_names[$i]) eq "_ADMIN") ||
			(($vol_names[$i]) =~ m/IV_$/) ||
			(($vol_names[$i]) eq ".") ||
			(($vol_names[$i]) eq "..")) {
				splice(@vol_names,$i,1);
		} else {
			$i++;
		}
	}
	return @vol_names;
}

#---------------------------(  mail_results  )--------------------------#
#  FUNCTION:    mail_results						#
#                                                                       #
#  PURPOSE:     Send an SMTP Status Message with Program Results	#
#                                                                       #
#  ARGS:        $recipient - Recipient Address of the Message		#
#		$relay - Server to Receive the Message			#
#		$sender - Sender Address of the Message			#
#-----------------------------------------------------------------------#
sub mail_results {
	# Passed Variables
	my $recipient=$_[0]; # Passed Mail Recipient Variable
	my $relay=$_[1]; # Passed SMTP Relay Variable
	my $sender=$_[2]; # Passed Sender Variable
   
	# Local Variables
	my @fulldata; # Array for Full Backup File Contents
	my @postdata; # Array for Post Backup File Contents
	my $smtp=Net::SMTP->new($relay); #Instantiate the Library
	my $boundary="frontier"; # Define Mail Boundary

	# Parse Full Backup File into Email
	@fulldata=parse_file($datadir.$fullbackup);
	@postdata=parse_file($datadir.$postprocess);
   
	$smtp->mail($sender);
	$smtp->recipient($recipient,{SkipBad=>1});
	$smtp->data();
	$smtp->datasend("Subject: Reports\n");
	$smtp->datasend("MIME-Version: 1.0\n");
	$smtp->datasend("Content-type: multipart/mixed;\n\tboundary=\"$boundary\"\n");
	$smtp->datasend("\n");
	$smtp->datasend("--$boundary\n");
	$smtp->datasend("Content-type: text/plain\n");
	$smtp->datasend("Content-Disposition: quoted-printable\n");
	$smtp->datasend("\nTrustee Rights CSV Files are Attached:\n\n");
	# List Each Processed Directory
	foreach(@userpaths) {
		$smtp->datasend("Processed Directory: $_\n");
	}
	$smtp->datasend("\nHave a nice day! :)\n");
	$smtp->datasend("--$boundary\n");
	$smtp->datasend("Content-Type: application/text; name=\"$fullbackup\"\n");
	$smtp->datasend("Content-Disposition: attachment; filename=\"$fullbackup\"\n");
	$smtp->datasend("\n");
	$smtp->datasend("@fulldata\n");
	$smtp->datasend("--$boundary\n");
	$smtp->datasend("Content-Type: application/text; name=\"$postprocess\"\n");
	$smtp->datasend("Content-Disposition: attachment; filename=\"$postprocess\"\n");
	$smtp->datasend("\n");
	$smtp->datasend("@postdata\n");
	$smtp->datasend("--$boundary\n");
	$smtp->dataend();
	$smtp->quit;
}

#-------------------------( new_rights )--------------------------------#
#  FUNCTION:	new_rights						#
#  PURPOSE:	Refactor Rights File for Import with New Rights		#
#		Structure From User Input and Trustee Backup		#
#-----------------------------------------------------------------------#
sub new_rights {
        my @contents; # Array for Trustee Parsing Contents

	my $utility; # Variable to Contain Generating Utilty for CSV
	my $rightpath; # Path of Trustee Privileges from CSV Data
	my $inputline; # Line of Data from User Input
	my $remainder; # Variable to Contain All Other CSV Data

	# Parse Existing Trustee Rights into Contents Array
        @contents=parse_file($datadir.$fullbackup);

	# Loop through Input File and Compare to Existing Trustees
	foreach $inputline (@userpaths) {
		my $index = 0;
		while ($index <= $#contents ) {
			my $value = $contents[$index];
			($utility,$rightpath,$remainder)=split(",",$value,3);
			# Remove Quotes from Directory Path Field
			$rightpath=~s/\"//g;
			# Remove Matches from Array
			if ($rightpath eq $inputline) {
				print "$rightpath | $trueline\n";
				splice @contents,$index,1;
			} else {
				$index++;
			}
		}
	}
	sleep 4;
	# Write New Changes to File
	write_file(@contents);
}

#----------------------------(  parse_file  )---------------------------#
#  FUNCTION:	parse_file						#
#  PURPOSE:	Parse User Input CSV from Quest NDS Migrator into 	#
#		Directory Paths for Rights Removal and load into Array.	#
#									#
#  ARGS:	$csvfile - CSV Input File with Right Alterations	#
#									#
#  RETURNS:	@pathresults - Formatted Output Array in File Syntax	# 
#-----------------------------------------------------------------------#
sub parse_csv {
	# Passed Subroutine Variables
	my $csvfile=$_[0]; #CSV Input File

	# Local Variables
	my @contents; # File Contents From Parsing
	my @pathresults; # Array with Home Directory Data
	my $userid; # User Name Field Data
	my $userpath; # User Home Directory Field Data

	# Acquire File Parse Results
	@contents=parse_file($csvfile);
	
	# Rewrite Home Directory Paths
	foreach (@contents) {
		# Skip CSV Header Line
		next if (/UserID,NDSMap/);
		($userid, $userpath) = split(" ");
		# Regex Isolate the Server Relative Paths
		$userpath =~ s/^NDS:\/\/$treename\\\\$host\\//g;
		$userpath =~ s/(\\HOME.+)/:$+/g;
		# Write Reformatted Paths to Results Array
		push(@pathresults,$userpath);
	}
	# Return Parsed Results to Calling Function
	return @pathresults;	
}

#----------------------------(  parse_file  )-----------------------------------#
#  FUNCTION:	parse_file							#
#										#
#  PURPOSE:	Slurp file for data into array and close file handle.  		#
#										#
#  ARGS:	$file - Input File for Parsing					#
#										#
#  RETURNS:	@contents - File Contents in Array				#
#-------------------------------------------------------------------------------#
sub parse_file {
	# Passed in Variables
	my $file=$_[0];
	
	# Local Variables
	my @contents; # Array to hold file contents;
	
	# Open File Handle and Slurp Contents to Array
	open(FILE,"<".$file) || die "could not open file: $!";
		@contents=<FILE>;
	close(FILE);
	return @contents;
}

#----------------------------(  prompt_user  )--------------------------#
#  FUNCTION:	prompt_user						#
#									#
#  PURPOSE:	Prompt the user for some type of input, and return the	#
#		input back to the calling program.			#
#									#
#  ARGS:	$promptString - what you want to prompt the user with	#
#		$defaultValue - (optional)  default value for the prompt#
#-----------------------------------------------------------------------#
sub prompt_user {
	#-------------------------------------------------------------------#
	#  two possible input arguments - $promptString, and $defaultValue  #
	#  make the input arguments local variables.                        #
	#-------------------------------------------------------------------#
	my($promptString,$defaultValue) = @_;

	#-------------------------------------------------------------------#
	#  if there is a default value, use the first print statement; if   #
	#  no default is provided, print the second string.                 #
	#-------------------------------------------------------------------#

	if ($defaultValue) {
		print $promptString, "[", $defaultValue, "]: ";
	} else {
		print $promptString, ": ";
	}

	$| = 1;		# force a flush after our print
	$_ = <STDIN>;	# get the input from STDIN (presumably the keyboard)

	# Strip Newline on Carriage Return
	chomp;

	#---------------------------------------------------------------#
	#  if we had a $default value, and the user gave us input, then	#
	#  return the input; if we had a default, and they gave us no	#
	#  no input, return the $defaultValue.				#
	#								# 
	#  if we did not have a default value, then just return whatever#
	#  the user gave us.  if they just hit the <enter> key,		#
	#  the calling routine will have to deal with that.		#
	#---------------------------------------------------------------#
	if ("$defaultValue") {
		return $_ ? $_ : $defaultValue;    # return $_ if it has a value
	} else {
		return $_;
	}
}

#----------------------------(  wait_for_nlm  )---------------------------------#
#  FUNCTION:	wait_for_nlm							#
#										#
#  PURPOSE:	Loop while an NLM Remains Loaded				#
#-------------------------------------------------------------------------------#
sub wait_for_nlm {   	
	# Local Variables
	my $i=0; # Loop Counter for Module Time Bailout

	print "$nlm is processing";

	# Determine Module Running Status
	my $cmd_status=get_module_status($nlm);
	while ($cmd_status!=0) {
		print ".";
		# Wait Before Trying Again
		sleep(1);
		$cmd_status=get_module_status($nlm);
		if ($i==$timeout) {
			die "Operation Timeout on Waiting for: $nlm.";
		}
		$i++;
	}
	print "\n";
}

#----------------------------(  write_file  )-----------------------------------#
#  FUNCTION:	write_file							#
#										#
#  PURPOSE:	Write Array Data to File and Close File Handle  		#
#										#
#  ARGS:	$file - Output File for Writing					#
#										#
#  RETURNS:	@contents - File Contents in Array				#
#-------------------------------------------------------------------------------#
sub write_file {
	# Array Data to Write
	my @contents=@_;
	
	# Open File Handle and Slurp Contents to Array
	open(FILE,">".$datadir.$newrights) || die "could not open file: $!";
		print FILE @newrights;
	close(FILE);
}
