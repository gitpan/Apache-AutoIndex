#$Id: AutoIndex.pm,v 1.14 1999/02/10 08:49:11 gozer Exp $
package Apache::AutoIndex;

use strict;
use Apache::Constants qw(:common OPT_INDEXES DECLINE_CMD REDIRECT DIR_MAGIC_TYPE);
use DynaLoader ();
use Apache;
use Apache::Util qw(ht_time size_string);
use Apache::ModuleConfig;
use Apache::Icon;
use Apache::Language;

use vars qw ($VERSION @ISA);
use vars qw ($nDir $nRedir $nIndex %sortname);

@ISA = qw(DynaLoader);
$VERSION="0.06";

#Configuration constants
use constant FANCY_INDEXING 	=> 1;
use constant ICONS_ARE_LINKS 	=> 2;
use constant SCAN_HTML_TITLES 	=> 4;
use constant SUPPRESS_LAST_MOD	=> 8;
use constant SUPPRESS_SIZE  	=> 16;
use constant SUPPRESS_DESC 	    => 32;
use constant SUPPRESS_PREAMBLE 	=> 64;
use constant SUPPRESS_COLSORT 	=> 128;
use constant THUMBNAILS 	    => 256;
use constant SHOW_PERMS         => 512;
use constant NO_OPTIONS		    => 1024;

#Default values
use constant DEFAULT_ICON_WIDTH => 20;
use constant DEFAULT_ICON_HEIGHT=> 22;
use constant DEFAULT_NAME_WIDTH => 23;
use constant DEFAULT_ORDER	=> "ND";

my $debug;  

#this should be a constant
my %sortname =	( 	
            'N'	=> 	'Name' ,
			'M'	=>	'LastModified',
			'S'	=>	'Size',
			'D'	=>	'Description',
		);
			
#Statistics variables
$nDir=0;
$nRedir=0;
$nIndex=0;

if ($ENV{MOD_PERL}){
	__PACKAGE__->bootstrap($VERSION);
	if (Apache->module('Apache::Status')){
		Apache::Status->menu_item('AutoIndex' => 'Apache::AutoIndex status', \&status);
		}
}

sub IndexOptions($$$;*){
	my ($cfg, $parms, $directives, $cfg_fh) = @_;
	foreach (split /\s+/, $directives){
		my $option;
		(my $action, $_) = (lc $_) =~ /(\+|-)?(.*)/;
		
        if (/^fancyindexing$/){
			$option = FANCY_INDEXING;
			} 
		elsif (/^iconsarelinks$/){
			$option = ICONS_ARE_LINKS;
			} 
		elsif (/^scanhtmltitles$/){
			$option = SCAN_HTML_TITLES;
			}
		elsif (/^suppresslastmodified$/){
			$option =  SUPPRESS_LAST_MOD;
			}
		elsif (/^suppresssize$/){
			$option =  SUPPRESS_SIZE;
			}
		elsif (/^suppressdescription$/){
			$option =  SUPPRESS_DESC;
			}
		elsif (/^suppresshtmlperamble$/){
			$option =  SUPPRESS_PREAMBLE;
			}
		elsif (/^suppresscolumnsorting$/){
			$option =  SUPPRESS_COLSORT;
			}
		elsif (/^thumbnails$/){
			$option = THUMBNAILS;
			}
        elsif (/^showpermissions$/){
            $option = SHOW_PERMS;
            }
		elsif (/^none$/){
			die "Cannot combine '+' or '-' with 'None' keyword" if $action;
			$cfg->{options} = NO_OPTIONS;
			$cfg->{options_add} = 0;
			$cfg->{options_del} = 0;
			}
		elsif (/^iconheight(=(\d*$|\*$)?)?(.*)$/){
			die "Bad IndexOption $_ directive syntax" if ($3 || ($1 && !$2));
			if ($2) {
				die "Cannot combine '+' or '-' with IconHeight" if $action;
				$cfg->{icon_height} = $2;
				}
			else 	{
				if ($action eq '-') {
					$cfg->{icon_height} = DEFAULT_ICON_HEIGHT;
					}
				else    {
					$cfg->{icon_height} = 0;
					}
				}
			}
		elsif (/^iconwidth(=(\d*$|\*$)?)?(.*)$/){
			die "Bad IndexOption $_ directive syntax" if ($3 || ($1 && !$2));
			if ($2) {
				die "Cannot combine '+' or '-' with IconWidth" if $action;
				$cfg->{icon_width} = $2;
				}
			else 	{
				if ($action eq '-') {
					$cfg->{icon_width} = DEFAULT_ICON_WIDTH;
					}
				else    {
					$cfg->{icon_width} = 0;
					}
				}
			}
		
		elsif (/^namewidth(=(\d*$|\*$)?)?(.*)$/){
			die "Bad IndexOption $_ directive syntax" if ($3 || ($1 && !$2));
			if ($2) {
				die "Cannot combine '+' or '-' with NameWidth" if $action;
				$cfg->{name_width} = $2;
				}
			else 	{
				die "NameWidth with no value can't be used with '+'" if ($action ne '-');
				$cfg->{name_width} = 0;
				}
			}
		else {
 warn "IndexOptions unknown/unsupported directive $_";
			}
		
		if (! $action) {
			
			$cfg->{options} |= $option;
			$cfg->{options_add} = 0;
			$cfg->{options_del} = 0;
			}
		elsif ($action eq '+') {
			
			$cfg->{options_add} |= $option;
			$cfg->{options_del} &= ~$option;
			}
		elsif ($action eq '-') {
			
			$cfg->{options_del} |= $option;
			$cfg->{options_add} &= ~$option;
			}
		if (($cfg->{options} & NO_OPTIONS) && ($cfg->{options} & ~NO_OPTIONS)) {
			die "Canot combine other IndexOptions keywords with 'None'";
			}
	}
return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;
}

# e.g. DirectoryIndex index.html index.htm index.cgi 
sub DirectoryIndex($$$;*){
	my ($cfg, $parms, $files, $cfg_fh) = @_;
	for my $file (split /\s+/, $files){
		push @{$cfg->{index}}, $file;
	}
return Apache->module('mod_dir.c') ? DECLINE_CMD : OK;
}

sub AddDescription($$$;*){
	my ($cfg, $parms, $args, $cfg_fh) = @_;
	my ($desc, $files) = ( $args =~ /^\s*"([^"]*)"\s+(.*)$/);
	my $file = join "|", split /\s+/, $files;
	$file =~ s/\./\\./g;
    $file =~ s/\*/.*/g;
	$file =~ s/\?/./g;
    $cfg->{desc}{$file} = $desc; 
return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;
}

sub IndexOrderDefault($$$;*){
	my ($cfg, $parms, $string, $cfg_fh) = @_;
	my ($order, $key ) = split /\s+/, $string;
	die "First Keyword must be Ascending or ending" unless ( $order =~ /^(de|a)scending$/i);
	die "First Keyword must be Name, Date, Size or Description" unless ( $key =~ /^(date|name|size|description)$/i);
	if ($key =~ /date/i){
		$key = 'M';
		}
	else {
	    $key =~ s/(.).*$/$1/;
	}
	$order =~ s/(.).*$/$1/;
	$cfg->{default_order} = $key . $order;

return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;
}

sub FancyIndexing ($$$) {
	my ($cfg, $parms, $arg) = @_;
	die "FancyIndexing directive conflicts with existing INdexOptions None" if ($cfg->{options} & NO_OPTIONS);
	my $opt = ( $arg =~ /On/ ) ? 1 : 0;
	$cfg->{options} = ( $opt ? ( $cfg->{options} | FANCY_INDEXING ) : ($cfg->{options} & ~FANCY_INDEXING ));
return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;
}

sub IndexIgnore($$$;*){
	my ($cfg, $parms, $files, $cfg_fh) = @_;
	for my $file (split /\s+/, $files){
		$file =~ s/\./\\./g;
		$file =~ s/\*/.+/g;
		$file =~ s/\?/./g;
		push @{$cfg->{ignore}}, $file;
	}
return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;
}

sub ReadmeName($$$;*){
	my ($cfg, $parms, $files, $cfg_fh) = @_;
	for my $file (split /\s+/, $files){
		die "Relative File Names only" if $file =~ m:^/: ;
		push @{$cfg->{readme}}, $file;
	}
return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;
}

sub HeaderName ($$$;*) {
	my ($cfg, $parms, $files, $cfg_fh) = @_;
	for my $file (split /\s+/, $files){
	    push @{$cfg->{header}}, $file;
	    }
return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;
}

sub DIR_MERGE {
	my ($parent, $current) = @_;
	my %new;
    $new{options_add} = 0;
    $new{options_del} = 0;
	$new{icon_height} = $current->{icon_height} ? $current->{icon_height} : $parent->{icon_height};
	$new{icon_width} = $current->{icon_width} ? $current->{icon_width} : $parent->{icon_width};
	$new{name_width} = $current->{name_width} ? $current->{name_width} : $parent->{name_width};
	$new{default_order} = $current->{default_order} ? $current->{default_order} : $parent->{default_order};
	$new{readme} = [ @{$current->{readme}}, @{$parent->{readme}} ];
	$new{header} = [ @{$current->{header}}, @{$parent->{header}} ];
	$new{ignore} = [ @{$current->{ignore}}, @{$parent->{ignore}} ];
	$new{index} = [ @{$current->{index}}, @{$parent->{index}} ];
	
    $new{desc} = {% {$current->{desc}}};    #Keep descriptions local
	
	if ($current->{options} & NO_OPTIONS){
		$new{options} = NO_OPTIONS;
		}
	else {
		if ($current->{options} == 0) {
			$new{options_add} = ( $parent->{options_add} | $current->{options_add}) & ~$current->{options_del};
			$new{options_del} = ( $parent->{options_del} | $current->{options_add}) ;
			$new{options} = $parent->{options} & ~NO_OPTIONS;
			}
		else {
			$new{options} = $current->{options};
			}
		
        $new{options} |= $new{options_add};
		$new{options} &= ~ $new{options_del};
		}
return bless \%new, ref($parent);
}

sub new { 
	return bless {}, shift;
	}
	
sub DIR_CREATE {
	my $class = shift;
	my $self = $class->new;
	$self->{icon_width} = DEFAULT_ICON_WIDTH;
	$self->{icon_height} = DEFAULT_ICON_HEIGHT;
	$self->{name_width} = DEFAULT_NAME_WIDTH;
	$self->{default_order} = DEFAULT_ORDER;
	$self->{ignore} = [];
	$self->{readme} = [];
	$self->{header} = [];
	$self->{index} = [];
	$self->{desc} = {};
	$self->{options} = 0;
	$self->{options_add} = 0;
	$self->{options_del} = 0;
return $self;
}
sub dir_index {
	my($r) = @_;
	my $lang = new Apache::Language ($r);
	my %args = $r->args;
	my $name = $r->filename;
	my $cfg = Apache::ModuleConfig->get($r);
	my $subr;
	$r->filename("$name/") unless $name =~ m:/$:; 
        
	unless (opendir DH, "$name"){
		$r->log_reason( __PACKAGE__ . " Can't open directory for index", $r->uri . " (" . $r->filename . ")");
	return FORBIDDEN;
	}
	$nDir++;

    
	print "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\" \"http://www.w3.org/TR/REC-html40/loose.dtd\">\n<HTML><HEAD>\n<TITLE>" . $lang->message("Header") . $r->uri . "</TITLE></HEAD>";
    
 #warn This should be configurable...
    print "<BODY BACKGROUND=\"$ENV{background}\" VLINK=\"#730000\">\n";
	
    if (not $cfg->{options} & FANCY_INDEXING){
        print "<UL>\n";
        foreach my $file ( readdir DH ){
            print "\t<LI><A HREF=\"$file\">$file</A></LI>\n";
            }
        print "</UL></BODY></HTML>\n";
    return OK;
    }

    
	print "<H2>" . $lang->message("Header") . $r->uri . "</H2>\n" ;
	
    place_doc($r, $cfg, 'header');
	
	print qq{<HR><TABLE BORDER="0" CELLSPACING="0" CELLPADDING="0" WIDTH="100% "><TR>};
 	
 	my $list = read_dir( $r, \*DH );
   
    %args = {} if ($cfg->{options} & SUPPRESS_COLSORT);
   
    my $listing = do_sort($list, \%args, $cfg->{default_order});
    if ($cfg->{options} & SHOW_PERMS) {
        print "<TH>Perms</TH>" ;
        }
    
 	foreach ('N', 'M', 'S', 'D'){
    next if( $cfg->{options} & SUPPRESS_LAST_MOD && $_ eq 'M');
    next if( $cfg->{options} & SUPPRESS_SIZE && $_ eq 'S');
    next if( $cfg->{options} & SUPPRESS_DESC && $_ eq 'D');
    print "<TH>";
 	if (not $cfg->{options} & SUPPRESS_COLSORT){
        if ($args{$_}){
 	        my $query = ($args{$_} eq "D") ? 'A' : 'D';
 	        print "<A HREF=\"?$_=$query\"><I>" . $lang->message($sortname{$_}) . "</I></A>";
        } else {
 	        print "<A HREF=\"?$_=D\">" . $lang->message($sortname{$_}) . "</A>";
 	        }
        }
    else {
        print $lang->message($sortname{$_});
        }
    print "</TH>";
    }
   
    print "</TR>";
    
	for my $entry (@$listing) {
	    my $img;
 	    if(($list->{$entry}{type} =~ m:^image/:) && ($cfg->{options} & THUMBNAILS )) {
  	        #use the image itself for the icon
  	        $img = $entry;
  		    }
  	    else 	{
 	    	    $img = $list->{$entry}{icon};
 		    }		      

	    my $label = $entry eq '..'  ? $lang->message('Parent') : $entry;

	    print qq{<TR valign="bottom">};

        print "<TD>" . $list->{$entry}{mode} . "</TD>" if ($cfg->{options} & SHOW_PERMS);

	    print "<TD><img width=20 height=22 src=\"$img\" alt=\"[$list->{$entry}{alt}]\"><a href=\"$entry";
	    print "/" if $list->{$entry}{sizenice} eq '-';
	    print "\">$label</a></TD>";

	    print "<TD>$list->{$entry}{modnice}</TD>" unless ( $cfg->{options} & SUPPRESS_LAST_MOD );

	    print "<TD align=\"center\">" . $list->{$entry}{sizenice} . "</TD>" unless ( $cfg->{options} & SUPPRESS_SIZE );

	    print "<TD>". $list->{$entry}{desc} . "</TD>" unless ( $cfg->{options} & SUPPRESS_DESC );

        print "</TR>\n";	  
    }
	
    print "</TABLE>\n";
	
	
	place_doc($r, $cfg, 'readme');
	
	
	print " <HR>" . $ENV{'SERVER_SIGNATURE'};
	if ($debug) {
		use Data::Dumper;
		print "<PRE>";
		print "<HR>\%list<BR><BR>";
		print Dumper \%$list;
		print "<HR>\@listing<BR><BR>";
		print Dumper \@$listing;
		print "<HR>DUMP<BR><BR>";
		print Dumper $cfg;
		}
	
    print "</BODY></HTML>";

return OK
}

	
sub read_dir {
    my ($r, $dirhandle) = @_;
    my $cfg = Apache::ModuleConfig->get($r);
    my @listing;
    my %list;
    while (my $file = readdir $dirhandle) {
		foreach (@{$cfg->{ignore}}) {
			if ($file =~ m/^$_$/){
				$file = '.';
				last;
				}
			}
		next if $file eq '.';
        push @listing, $file;
		}
		foreach my $file (@listing){
		my $subr = $r->lookup_file($file);
		stat $subr->finfo;
		$list{$file}{size} = -s _;
		if (-d _){
            $list{$file}{size} = -1;
            $list{$file}{sizenice} = '-';
		        }
        else {
            $list{$file}{sizenice} = size_string($list{$file}{size});
                }
        $list{$file}{mod}  = (stat _)[9];
        $list{$file}{modnice} = ht_time($list{$file}{mod}, "%d-%b-%Y %H:%M", 0);
		$list{$file}{mode} = write_mod((stat _)[2]);
    	$list{$file}{type}  = $subr->content_type;
	    my $icon = Apache::Icon->new($subr);
		$list{$file}{icon} = $icon->find;           
	    if (-d _) {	
			$list{$file}{icon} ||= $icon->default('^^DIRECTORY^^');	
			$list{$file}{alt} = "DIR";
			}	    
		$list{$file}{icon} ||= $icon->default;
		$list{$file}{alt} ||= $icon->alt; 
		$list{$file}{alt} ||= "???"; 
	 	if ($list{$file}{type} eq "text/html" and ($cfg->{options} & SCAN_HTML_TITLES)){
            use HTML::HeadParser;
            my $parser = HTML::HeadParser->new;
            open FILE, $subr->filename;
            while (<FILE>){
                last unless $parser->parse($_);
                }
            $list{$file}{desc} = $parser->header('Title');
            close FILE;
            }
        foreach (keys %{$cfg->{desc}}){
            $list{$file}{desc} = $cfg->{desc}{$_} if $subr->filename =~ /$_/;
            }
        }
return \%list;
}    

sub transhandler {
    my $r = shift;
	return DECLINED unless $r->uri =~ /\/$/;
	my $cfg = Apache::ModuleConfig->get($r);
    foreach (@{$cfg->{index}}) {
		my $subr = $r->lookup_uri($r->uri . $_);
    	if (stat $subr->finfo) {
    	    $nIndex++;
            $r->uri($subr->uri);
            last;
        }
    }
return DECLINED;
}

sub handler {
	my $r = shift;
	return DECLINED unless $r->content_type and $r->content_type eq DIR_MAGIC_TYPE;
	
	unless ($r->path_info) {
		my $uri = $r->uri;
		my $query = $r->args;
		$query = "?" . $query if $query;
		$r->header_out(Location => "$uri/$query");
		$nRedir++;
	return REDIRECT;	
	}  
    
	my $cfg = Apache::ModuleConfig->get($r);
	$debug = $r->dir_config('AutoIndexDebug');

	if($r->allow_options & OPT_INDEXES) {
	    $r->send_http_header("text/html");
	    return OK if $r->header_only;
	    return dir_index($r);
	
	} else {
		$r->log_reason( __PACKAGE__ . " Directory index forbidden by rule", $r->uri . " (" . $r->filename . ")");
	return FORBIDDEN;
	}
}


sub do_sort {
	my ($list, $query, $default) = @_;
    my @names = sort keys %$list;
    shift @names;                   #removes '..'
    
    #handle default sorting
	unless ($query->{N} || $query->{S} || $query->{D} || $query->{M})
		{
		$default =~ /(.)(.)/;
		$query->{$1} = $2;
		}
	
	if ($query->{N}) {
		@names = sort @names if $query->{N} eq "D";
		@names = reverse sort @names if $query->{N} eq "A";
	} elsif ($query->{S}) {
		@names = sort { $list->{$b}{size} <=> $list->{$a}{size} } @names if $query->{S} eq "D";
		@names = sort { $list->{$a}{size} <=> $list->{$b}{size} } @names if $query->{S} eq "A";
	} elsif ($query->{M}) {
		@names = sort { $list->{$b}{mod} <=> $list->{$a}{mod} } @names if $query->{M} eq "D";
		@names = sort { $list->{$a}{mod} <=> $list->{$b}{mod} } @names if $query->{M} eq "A";		
	} elsif ($query->{D}) {
		@names = sort { $list->{$b}{desc} cmp $list->{$a}{desc} } @names if $query->{D} eq "D";
		@names = sort { $list->{$a}{desc} cmp $list->{$b}{desc} } @names if $query->{D} eq "A";		
		}
	
unshift @names, '..';           #puts back '..' on top of the pile
return \@names;
}


sub place_doc {
	my ($r, $cfg, $type) = @_;
	foreach (@{$cfg->{$type}}) {
    		my $subr = $r->lookup_uri($r->uri . $_);
    		
			if (stat $subr->finfo) {
    			print "<HR>" if $type eq "readme";
    			print "<PRE>" unless m/\.html$/;
			$subr->run;
       		     	print "</PRE>" unless m/\.html$/;
       		     	print "<HR>" if $type eq "header";
			}
    		else	{
    			$subr = $r->lookup_uri($r->uri . $_ . ".html");
    			if (stat $subr->finfo) {
    				print "<HR>";
    				$subr->run;
    				}
    			}
    	}
}

sub write_mod {
    my $mod = shift ;
    $mod = $mod & 4095;
    my $letters;
    my %modes = (
                1   =>  'x',
                2   =>  'w',
                4   =>  'r',
                );
    foreach my $f (64,8,1){
        foreach my $key (4,2,1){
            if ($mod & ($key * $f)){
                $letters .= $modes{$key};
                }
            else {
                $letters .= '-';
                }
            }
    }
return $letters;
}


sub status {
	my ($r, $q) = @_;
	my @s;
	my $cfg = Apache::ModuleConfig->get($r);
	push (@s, "<B>" , __PACKAGE__ , " (ver $VERSION) statistics</B><BR>");

	push (@s , "Done " . $nDir . " listings so far<BR>");
	push (@s , "Done " . $nRedir . " redirects so far<BR>");
	push (@s , "Done " . $nIndex. " indexes so far<BR>");
	
return \@s;
}

1;

__END__

=head1 NAME

Apache::AutoIndex - Perl replacment for mod_autoindex and mod_dir Apache module

=head1 SYNOPSIS

  PerlModule Apache::Icon
  PerlModule Apache::AutoIndex
  PerlTransHandler Apache::AutoIndex::transhandler
  PerlHandler Apache::AutoIndex

=head1 DESCRIPTION

This module can replace completely mod_dir and mod_autoindex
standard directory handling modules shipped with apache.
It can currently live right on top of those modules, but I suggest
simply making a new httpd without these modules compiled-in.

To start using it on your site right away, simply preload
Apache::Icon and Apache::AutoIndex either with:

  PerlModule Apache::Icon
  PerlModule Apache::AutoIndex

in your httpd.conf file:

   use Apache::Icon ();
   use Apache::AutoIndex;
 
in your require.pl file.

Then it's simply adding

    PerlTransHandler Apache::Autoindex::transhandler
    PerlHandler Apache::AutoIndex 

somewhere in your httpd.conf but outside any Location/Directory containers.


=head2 VIRTUAL HOSTS

If used in a server using virtual hosts, since mod_perl doesn't have configuration merging routine for virtual hosts, you'll have to put the PerlHandler and PerlTransHandler directives in each and every <VHOST></VHOST> 
section you wish to use Apache::AutoIndex with.

=head1 DIRECTIVES

It uses all of the Configuration Directives defined by mod_dir and mod_autoindex.  

Since the documentation about all those directives can be found
on the apache website at:

 http://www.apache.org/docs/mod/mod_autoindex.html 
 http://www.apache.org/docs/mod/mod_dir.html

I will only list modification that might have occured in this
perl version.

=head2 SUPPORTED DIRECTIVES

=over

=item *

AddDescription

=item *

DirectoryIndex

=item *

FancyIndexing - should use IndexOptions FancyIndexing since 1.3.2

=item *

IndexOptions  - All directives are currently supported. And a few were added

=item *

HeaderName  - It can now accept a list of files instead of just one

=item *

ReadmeName  - It can now accept a list of files instead of just one

=item *

IndexIgnore

=item *

IndexOrderDefault

=back

=head2 NEW DIRECTIVES

=over

=item * IndexOptions

Thumbnails - Icons for images are small thumbnails.  Defaults to false.

ShowPermissions - prints file permissions. Defaults to false.

=item * PerlSetVar AutoIndexDebug [0|1]

If set to 1, the listing displayed will print usefull (well, to me)
debugging information appended to the bottom. The default is 0.

=back

=head2 UNSUPPORTED DIRECTIVES

=over

=item * - Hopefully none :-)
 
=back

=head1 TODO

Generation of thumbnails with Apache::Magik instead of simply linking on the
actual image.  And some sort of caching of thumbnails also.

Find new things to add...

=head1 SEE ALSO

perl(1), L<Apache>(3), L<Apache::Icon>(3).

=head1 SUPPORT

Please send any questions or comments to the Apache modperl 
mailing list <modperl@apache.org> or to me at <gozer@ectoplasm.dyndns.com>

=head1 NOTES

This code was made possible by :

=over

=item *

Doug MacEachern <dougm@pobox.com>  Creator of Apache::Icon, and of course, mod_perl.

=item *

Rob McCool who produced the final mod_autoindex.c I copied, hrm.., well, translated to perl.

=item *

The mod_perl mailing-list at <modperl@apache.org> for all your mod_perl related problems.

=back

=head1 AUTHOR

Philippe M. Chiasson <gozer@ectoplasm.dyndns.com>

=head1 COPYRIGHT

Copyright (c) 1999 Philippe M. Chiasson. All rights reserved. This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself. 

=cut
