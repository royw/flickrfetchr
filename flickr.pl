#!/usr/bin/perl
# usage : flickr.pl D W H S 
# D - day search range
# W - picture width
# H - picture height
# S - search string

use Flickr::API;
use XML::Simple;
use Image::Magick;
use Data::Dumper;
use DBI;
use POSIX qw(ceil floor);
use POSIX ":sys_wait_h";
#use strict;
use vars qw($dest $xs $r @buff $child_count $minW $minH @fileList @AoH);

# If the file /etc/pluto/flickr-enabled contains only "0" and whitespaces,
# then this script is disabled


if (-f '/etc/pluto/flickr-enabled')
{
	open CONF, '/etc/pluto/flickr-enabled';
	$enabled = <CONF>;
	close CONF;

	chomp($enabled);
	die ("Flickr is disabled") if ($enabled eq "0");
}
print "Starting flickr\n";

$child_count = 5;

$SIG{CHLD} = \&sig_child;

# touch the file /var/flickr_start if it doesn't exist
# touch the file every 5 hours if it does exist and the
# last line in the file is "Pictures downloaded"
# "Pictures downloaded" indicates that at least 20% of
# the pictures were downloaded

if (-e '/var/flickr_start'){
	my $line = `tail -n 1 /var/flickr_start`;
	chomp($line);
	if ($line eq 'Pictures downloaded'){
		my $currentTime = `date +%s`;
		my $lastRunTime = `stat --format=%Z /var/flickr_start`;
		my $nrSeconds = $currentTime - $lastRunTime;
		if ($nrSeconds > 18000){
			`touch /var/flickr_start`;
		} else {
#			exit (0);
		}
	}
} else {
	`touch /var/flickr_start`;
}

# Config section. ###########################################

my $fKey  = '74e14e217ff6bfb670ccec36c0aa122b'; # the flickr key
$dest  = '/home/flickr'; # Destination folder
symlink("/home/flickr","/home/public/data/pictures/flickr");
my $daycount = 0;
my ($tDays, $api, $response, $id, $buff, $IMGS, $search_string);

# Code body ##############################################
# my ($tDays,$minW,$minH,$api,$flag,$response,$xs,$r,$id,$buff,$IMGS,$ua,@buff,$tag,@tags,$finaldst,$fms,@out,$ffield,$search_string);
# my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);

# check script arguments 

if ( $#ARGV >= 0 ) {

	if ($ARGV[0]) {
		$tDays = $ARGV[0];
		print "Search days: $tDays";
	}
			
	if ($ARGV[1]) {
		$minW = $ARGV[1];
		print "\tMin width: $minW";
	}
					
	if ($ARGV[2]) {
		$minH = $ARGV[2];
		print "\tMin height: $minH\n";
	}

	if ($ARGV[3]) {
		$search_string = $ARGV[3];
		print "\tSearch string: $search_string";
	}
					
}

if ($#ARGV < 0) {
        $tDays = 5;
        $minW = 1000;
        $minH = 700;
	#$search_string = '';
	$search_string = 'flowers';
	#$search_string = 'red cars';
        print "[flickr.pl] Using default values - days: $tDays, width: $minW, height: $minH, no search string \n";
}
                                               
 
if (!-d $dest) {
	mkdir("$dest"); 
}

$api = new Flickr::API({'key' => $fKey});
my ($max_number, $picture_nr);
$max_number = getMaxNrFiles();
$picture_nr = 0;

if ($search_string){
        $response = $api->execute_method('flickr.photos.search',{
                'tags'=>"$search_string",
                'sort'=>'interestingness-desc'
        });
	if ($response->{success} == 1) {
		$xs = new XML::Simple;
		$r=XMLin($response->{_content});
		foreach $id (sort keys %{$r->{'photos'}->{'photo'}}) {
			last if ($picture_nr >= $max_number);
			my ($width, $height, $source, $download) = getPictureDimensions($id, $api);
			if ($download){
				#print ">>poza $id cu nr $picture_nr<<<\n";
				$IMGS->{$id}->{'secret'}=$r->{'photos'}->{'photo'}->{$id}->{'secret'};
				$IMGS->{$id}->{'width'}= $width;
				$IMGS->{$id}->{'height'}= $height;
				$IMGS->{$id}->{'source'}= $source;
				#$IMGS->{$id}->{'download'} = $download;
				$picture_nr++;
			}
		}
	}
	my $child_pid;
        foreach $id (keys %{$IMGS}) {
                $response = $api->execute_method('flickr.photos.getInfo',{'photo_id' => $id , 'secret' => $IMGS->{$id}->{'secret'}});
                if ($response->{success} == 1) {
			#print "get info for $id\n";
			$r=XMLin($response->{_content});
			$IMGS->{$id}->{'time'}=$r->{'photo'}->{'dates'}->{'posted'};
			$IMGS->{$id}->{'format'}=$r->{'photo'}->{'originalformat'};
			if (!$IMGS->{$id}->{'format'}){
				$IMGS->{$id}->{'format'}='jpg';
			}
			$IMGS->{$id}->{'username'}=$r->{'photo'}->{'owner'}->{'username'};
			$response= $api->execute_method('flickr.photos.getSizes',{'photo_id' => $id});
			if (!isFileOnDisk($id, $IMGS->{$id}, $search_string)){
				
				wait_child();

				if (!defined($child_pid = fork())) {
					die "cannot fork: $!";

				} elsif ($child_pid) {
					# I'm the parent
					next;

				} else {
					# I'm the child
					get_files($search_string, $IMGS->{$id}, $id);
					activate_image($id, $IMGS->{$id}, $search_string);
					CORE::exit(0);
					#exit(0);
				} 
			}
                } else {
                        print STDERR "Skipped $id during an error.\n";
                        print STDERR "Error Message : $response->{error_message}\n";
                }
	}
	#get_files($search_string);
} else {
	my $child_pid;
	while ( ($daycount < $tDays) and ($picture_nr < $max_number)) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (time()-($daycount*24*60*60));
		$year=1900+$year;
		$mon=$mon+1;
		$mon="0".$mon if($mon <= 9);
		$mday="0".$mday if ($mday <=9);

		print "[flickr.pl] Date: $year-$mon-$mday => Searching for files maching your criteria in gallery.\n";
		$response = $api->execute_method('flickr.interestingness.getList', {  
			'date' => "$year-$mon-$mday",
			'page' => '1',
			'per_page' => '50'
			});

		if ($response->{success} == 1) {
			$xs = new XML::Simple;
			$r=XMLin($response->{_content});
			foreach $id (sort keys %{$r->{'photos'}->{'photo'}}) {
				last if ($picture_nr >= $max_number);
				my ($width, $height, $source, $download) = getPictureDimensions($id, $api);
				if ($download){
					#print ">>poza $id cu nr $picture_nr<<<\n";
					$IMGS->{$id}->{'secret'}=$r->{'photos'}->{'photo'}->{$id}->{'secret'};
					$IMGS->{$id}->{'width'}= $width;
					$IMGS->{$id}->{'height'}= $height;
					$IMGS->{$id}->{'source'}= $source;
					#$IMGS->{$id}->{'download'} = $download;
					$picture_nr++;
				}
			}
		}
		$daycount++;
	}#while

	foreach $id (keys %{$IMGS}) {
		$response = $api->execute_method('flickr.photos.getInfo',{'photo_id' => $id , 'secret' => $IMGS->{$id}->{'secret'}});
		if ($response->{success} == 1) {
			$r=XMLin($response->{_content});
			$IMGS->{$id}->{'time'}=$r->{'photo'}->{'dates'}->{'posted'};
			$IMGS->{$id}->{'username'}=$r->{'photo'}->{'owner'}->{'username'};
			$IMGS->{$id}->{'format'}=$r->{'photo'}->{'originalformat'};
			if (!$IMGS->{$id}->{'format'}){
				$IMGS->{$id}->{'format'}='jpg';
			}
			#look for the file existence
			if (!isFileOnDisk($id, $IMGS->{$id},'')){
				if ($IMGS->{$id}->{'time'} > time()-($tDays*24*60*60)) {
					#print "Intru pt $id\n";
					wait_child();
					if (!defined($child_pid = fork())) {
						die "cannot fork: $!";
					} elsif ($child_pid) {
						# I'm the parent
						next;
					} else {
						# I'm the child
						print "CC: $child_count";
						get_files('', $IMGS->{$id}, $id);
						activate_image($id, $IMGS->{$id}, $search_string);
						CORE::exit(0);
					} 
				}
			}
		} else {
			print STDERR "Skipped $id during an error.\n";
			print STDERR "Error Message : $response->{error_message}\n";
		}
	}
}

#marked as downloaded if at least 20 procents of total pictures are downloaded
$min_nr=floor(($max_number*20)/100);
if ($picture_nr >= $min_nr) {
	open DATA, ">/var/flickr_start" or die "can't open /var/flickr_start";
	print DATA 'Pictures downloaded';
	close(DATA);
}

#resizing images
#resize_images();

#deleting old files;
delete_old();

sub get_files {
	my $pattern = shift;
	my $image = shift;
	my $buff = shift;
	
	my ($finaldst, $fms, @out, $ffield);

	if (($pattern ne '') and (!-d $dest."/".'tags')){
		if (!mkdir($dest."/".'tags')) {
			die "Cannot create ".$dest."/".'tags'."\n";
		}
	} 
	if ($pattern eq '') {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($image->{'time'});
		$year=1900+$year;
		$mon=$mon+1;
		$mon="0".$mon if($mon <= 9);
		$mday="0".$mday if ($mday <=9);

		if (!-d $dest."/".$year) {
			if (!mkdir($dest."/".$year)) {
				die "Cannot create ".$dest."/".$year."\n";
			}
		}
	
		if (!-d $dest."/".$year."/".$mon) {
			if (!mkdir($dest."/".$year."/".$mon)) {
				die "Cannot create ".$dest."/".$year."/".$mon."\n";
			}
		}
		
		if (!-d $dest."/".$year."/".$mon."/".$mday) {
			if (!mkdir($dest."/".$year."/".$mon."/".$mday)) {
				die "Cannot create ".$dest."/".$year."/".$mon."/".$mday."\n";
			}
		}

		$finaldst = $dest."/".$year."/".$mon."/".$mday."/".$buff.".".$image->{'format'};
	} else {
		$finaldst = $dest."/".'tags'."/".$buff.".".$image->{'format'};
	}

	`touch "$finaldst".lock`;
	`wget $image->{'source'} -O "$finaldst" 1>/dev/null 2>/dev/null`;
	`convert "$finaldst" -sample 75x75 "jpeg:$finaldst".tnj`;

	open TEST, ">>/var/log/pluto/Flickr.log";
	print TEST "Downloaded image $finaldst , created lockfile, created tnj \n";
		
	close(TEST);
}

sub activate_image {
	open TEST, ">>/var/log/pluto/Flickr.log";
	my $id = shift;
	my $image = shift; 
	my $pattern = shift;
	my $finaldst;

	if ($pattern eq '') 
	{
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($image->{'time'});
		$year=1900+$year;
		$mon=$mon+1;
		$mon="0".$mon if($mon <= 9);
		$mday="0".$mday if ($mday <=9);

		print TEST  $dest."/".$year."/".$mon."/".$mday."/".$id.".".$image->{'format'}."\n";
		$finaldst = $dest."/".$year."/".$mon."/".$mday."/".$id.".".$image->{'format'};
	} else {
		$finaldst = $dest."/".'tags'."/".$buff.".".$image->{'format'};
	}

	print TEST "-------------------\n";
	print TEST "Resizing image $finaldst \n";	
	print TEST "-------------------\n";
	my ($i, $width, $height, $symdest, $partdst);

	$symdest = "/home/public/data/pictures/flickr";
	`touch "$finaldst.lock"`;
	$partdst = $finaldst;
	$partdst =~ s/\/home\/flickr//g;  
	$symdest .= "$partdst";
	$width = $image->{'width'};
	$height = $image->{'height'};
	
	my $test_date = `date`;
	print TEST "Old image width: $width and height: $height\n";
	if (($width > 1024 || $height > 1024)||
	    ($width > 1024 && $height > 1024)) {
		if($width > $height){
			$height = floor(($height/$width)*1024);
			$height = 768 if($height > 768);
			$width = 1024;
		} 
		elsif($height > $width){
			$width = floor(($width/$height)*1024);
			$width = 768 if($width > 768);
			$height = 1024;
		}
		elsif($height == $width){
			$width = 768;
			$height = 768;
		}
		print TEST "Resizing: New image width: $width and height: $height\n";
	
		#$r=$xs->Scale(width=>$width, 
		#	      height=>$height);
		#warn "$r" if "$r";
		#$r=$xs->Write($finaldst);
		`/usr/bin/convert -sample "$width"x"$height" $finaldst $finaldst`;
		print "[flickr.pl] Writing file $finaldst.\n";
	}

	## Don't send the messages too fast
	sleep 1;
	print `date`;
	print TEST "1. Sending /usr/pluto/bin/MessageSend dcerouter -targetType template -r -o 0 2 1 819 13 $symdest\n";
	$fms = qx | /usr/pluto/bin/MessageSend dcerouter -targetType template -r -o 0 2 1 819 13 "$symdest" |; 
				
	## If the router is not available for the moment
	while ( $fms =~ m/Cannot communicate with router/ ) {
		printf "Waiting for router to come up";
		sleep 10;
		print TEST "2. Sending /usr/pluto/bin/MessageSend dcerouter -targetType template -r -o 0 2 1 819 13 \"$symdest\"\n";
		$fms = qx | /usr/pluto/bin/MessageSend dcerouter -targetType template -r -o 0 2 1 819 13 "$symdest" |;
	}
				
	`rm -f $finaldst.lock`;
	$fms =~ s/\n//g;
	@out = split (/:/, $fms);
	$ffield = $out[2];
	#warn "$r" if "$r";
					
	# second message send
	#	print "Fire-ing second messagesend event\n";
	
	print TEST "3. Sending /usr/pluto/bin/MessageSend dcerouter -targetType template -r -o 0 2 1 391 145 \"$ffield\" 122 30 5 \"*\"\n";
	qx | /usr/pluto/bin/MessageSend dcerouter -targetType template -r -o 0 2 1 391 145 "$ffield" 122 30 5 "*" |;

	
	close(TEST);
}

sub delete_old {
	# Remove old files
	#my $totalFiles = `find /home/flickr/ -name '*.jpg'  | wc -l`;
	open TEST, ">>/var/log/pluto/Flickr.log";
	#print TEST "\n\n-------------DELETING OLD----------------------\n\n";
	return if ($#fileList == -1);
	my $listOfFiles = `find /home/flickr/ -name '*.jpg'`;
	my @arrayOfFiles = split (/\n/, $listOfFiles);
	my $deleteAll = 0;
	my $count = 0;

	if ($#fileList >= $max_number) {
		$deleteAll = 1;
	} else {
		my $dim = $#arrayOfFiles+1;
		$count = $dim - $max_number;
	}	

	my $dbh = DBI->connect('dbi:mysql:pluto_media');

	foreach ( @arrayOfFiles ) {
		if (!isFileInList($_)){
			if ($deleteAll) {
				my $test_date = `date`;
				print TEST "$test_date Removing file: $_ \n";
				`rm -f $_`;
				`rm -f $_.id3` if (-e "$_.id3");
				markFileAsDelete($dbh,$_);
			}else {
				my $test_date = `date`;
				print TEST "$test_date Removing file: $_ \n";
				`rm -f $_`;
				`rm -f $_.id3` if (-e "$_.id3");
				markFileAsDelete($dbh,$_);
				$count--;
				last if ($count <= 0);
			}
		}
	}
	#print TEST "\n\n-------------DELETING END---------------------\n\n";
	close(TEST);
	qx | /usr/pluto/bin/MessageSend dcerouter -targetType template 0 1825 1 606 |;
}

sub isFileInList {
	my $file = shift;

	foreach (@fileList) {
		return 1 if ($_ eq $file);
	}
	return 0;
}

sub markFileAsDelete {
	my $dbh = shift;
	my $file = shift;

	my $filename = `basename $file`;
	my $path = `dirname $file`;

	chomp($filename); chomp($path);
	
	my $sql = "UPDATE File SET Missing = 1 WHERE Filename='$filename'";
	my $sth = $dbh->prepare($sql);
	$sth->execute || die "Sql Error";
}

sub getMaxNrFiles {
	my $dbh = DBI->connect('dbi:mysql:pluto_main');
	my $sth = $dbh->prepare("
		SELECT 
			IK_DeviceData 
		FROM 
			Device_DeviceData 
			INNER JOIN Device ON Device_DeviceData.FK_Device = Device.PK_Device
		WHERE 
			Device_DeviceData.FK_DeviceData=177 
			AND 
			Device.FK_DeviceTemplate = 12
	");
	$sth->execute || die "Sql Error";
	my $row = $sth->fetchrow_hashref;
	my $noOfFilesToKeep = $row->{IK_DeviceData};
	return $noOfFilesToKeep;
}

sub isFileOnDisk {
	my $id = shift;
	my $image = shift;
	my $pattern = shift;
	my $finaldst;

	if ($pattern eq '') 
	{
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($image->{'time'});
		$year=1900+$year;
		$mon=$mon+1;
		$mon="0".$mon if($mon <= 9);
		$mday="0".$mday if ($mday <=9);
		$finaldst = $dest."/".$year."/".$mon."/".$mday."/".$id.".".$image->{'format'};
	} else {
		$finaldst = $dest."/".'tags'."/".$buff.".".$image->{'format'};
	}
	#print "destinatia: $finaldst ";
	if (!-e $finaldst){
		push @AoH, { File => $finaldst, Width => $image->{'width'}, Height => $image->{'height'} };
		push (@fileList, $finaldst);
		return 0;
	}
	return 1;
}

sub getPictureDimensions {
	my $id = shift;
	my $api = shift;
	my ($buff, $width, $height, $source, $download);
	my $response= $api->execute_method('flickr.photos.getSizes',{'photo_id' => $id});
	if ($response->{success} == 1) {
		my $r=XMLin($response->{_content});
		foreach $buff (@{$r->{'sizes'}->{'size'}}) {
			if (($buff->{'width'} >= $minW && $buff->{'height'} >= $minH) && 
			     ($buff->{'width'} <= 2048 && $buff->{'height'} <= 2048) )  {
				#last if ($buff->{'width'} > $maxW || $buff->{'height'} >= $maxH);
				$width = $buff->{'width'};
				$height = $buff->{'height'};
				$source = $buff->{'source'};
				$download = 1;
				last;
			}
		}
		return ($width, $height, $source, $download);
	}
	return (0,0,0,0)
}

sub sig_child {

	my $waitedpid;
	while (($waitedpid = waitpid(-1,WNOHANG)) > 0) {
		print "reaped $waitedpid\n";
	}

	$child_count++;
	
	$SIG{CHLD} = \&sig_child; # loathe sysV
}

sub wait_child {
	while ($child_count <=0){
		sleep(1);
	}
	$child_count--;
}
