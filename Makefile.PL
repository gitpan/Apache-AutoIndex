package Apache::AutoIndex;

use strict;
use Apache::src ();
use Apache::ExtUtils qw(command_table);
use ExtUtils::MakeMaker;

my $class = __PACKAGE__;

my @directives = (
	[DirectoryIndex => 'a list of files names'],
	[IndexIgnore    => 'one or more file extensions'],
	[IndexOptions   => 'one or more options'],
	[ReadmeName	=> ''],
	[HeaderName	=> ''],	
	[FancyIndexing  => ''],
	[IndexOrderDefault => ''],
);

command_table \@directives;

WriteMakefile(
	'NAME'	  	=> $class,
	'VERSION_FROM'	=> "AutoIndex.pm",
	'INC'		=> Apache::src->new->inc,
	'PREREQ_PM'	=> { 
				'Apache::Icon'  => '0.02',   
			     	'Apache'        => 0,
				'Apache::Status' => 0,
			   }, 
);
