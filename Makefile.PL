package Apache::AutoIndex;

use strict;
use Apache::src ();
use Apache::ExtUtils qw(command_table);
use ExtUtils::MakeMaker;

my $class = __PACKAGE__;

my @directives = (
	[DirectoryIndex => ''],
	[IndexIgnore    => 'one or more file extensions'],
	[IndexOptions   => 'one or more options'],
	[ReadmeName	=> ''],
	[HeaderName	=> ''],	
	[FancyIndexing  => ''],
	[IndexOrderDefault => ''],
	[AddDescription => ''],
);

command_table \@directives;

WriteMakefile(
	'NAME'	  	=> $class,
	'VERSION_FROM'	=> "AutoIndex.pm",            
	'INC'		=> Apache::src->new->inc,
	'PREREQ_PM'	=> { 
				'Apache::Icon'  => '0.02',   
				'HTML::HeadParser' => 0,
			     	'Apache'        => 0,
				'Apache::Status' => 0,
				'Apache::Language' => 0,
			   	'Storable'	=> 0,
				}, 
);
