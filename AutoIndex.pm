#$Id: AutoIndex.pm,v 1.8 1999/01/22 20:40:50 gozer Exp $
package Apache::AutoIndex;

use strict;
use Apache::Constants qw(:common OPT_INDEXES DECLINE_CMD REDIRECT DIR_MAGIC_TYPE);
use DynaLoader ();
use DirHandle ();
use Apache::Util qw(ht_time size_string);
use Apache::ModuleConfig;
use Apache::Icon;

use vars qw ($VERSION @ISA);
use vars qw ($nDir $nRedir $nIndex);

@ISA = qw(DynaLoader);
$VERSION="0.03";

my $debug;
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

# e.g. DirectoryIndex index.html index.htm index.cgi 
sub DirectoryIndex($$$;*){
	my ($cfg, $parms, $files, $cfg_fh) = @_;
	for my $file (split /\s+/, $files){
	push @{$cfg->{DirectoryIndex}}, $file;
	}

return Apache->module('mod_dir.c') ? DECLINE_CMD : OK;

}

sub IndexOptions($$$;*){
	my ($cfg, $parms, $options, $cfg_fh) = @_;
	for my $option (split /\s+/, $options){
	$cfg->{lc $option} = 1;
	}

return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;

}

sub FancyIndexing ($$$) {
	my ($cfg, $parms, $arg) = @_;
	$cfg->{FancyIndexing} = 0;
	$cfg->{FancyIndexing} = 1 if $arg =~ m/On/i;

return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;
}

sub IndexIgnore($$$;*){
	my ($cfg, $parms, $files, $cfg_fh) = @_;
	for my $file (split /\s+/, $files){
	$file =~ s/\./\\./g;
	$file =~ s/\*/.+/g;
	$file =~ s/\?/./g;
	push @{$cfg->{IndexIgnore}}, $file;
	}

return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;

}

sub ReadmeName($$$;*){
	my ($cfg, $parms, $files, $cfg_fh) = @_;
	for my $file (split /\s+/, $files){
		die "Relative File Names only" if $file =~ m:^/: ;
		push @{$cfg->{ReadmeName}}, $file;
	}

return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;

}

sub HeaderName($$$;*){
	my ($cfg, $parms, $files, $cfg_fh) = @_;
	for my $file (split /\s+/, $files){
	push @{$cfg->{HeaderName}}, $file;
	}

return Apache->module('mod_autoindex.c') ? DECLINE_CMD : OK;

}

sub DIR_MERGE {
	my ($parent, $current) = @_;
	my %new = (%$parent, %$current);
	return bless \%new, ref($parent);
}

sub dir_index {
    my($r) = @_;
    my %args = $r->args;
    my $name = $r->filename;
    my $cfg = Apache::ModuleConfig->get($r);
    my $dh;
    my $subr;
    
    $r->filename("$name/") unless $name =~ m:/$:; 
        
    unless ($dh = DirHandle->new($name)) {
	$r->log_reason( __PACKAGE__ . " Can't open directory for index", $r->uri . " (" . $r->filename . ")");
	return FORBIDDEN;
    }
	$nDir++;
    $r->send_http_header("text/plain") unless $r->content_type;
    return OK if $r->header_only;

	print "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.0 Transitional//EN\" \"http://www.w3.org/TR/REC-html40/loose.dtd\">\n<HTML><HEAD>";
	print "\n<TITLE>Directory index of " . $r->uri . "</TITLE></HEAD><BODY>\n";
	
		
	print "<H2>Directory index of " . $r->uri . "</H2><HR>\n" ;
	
	
	
	foreach (@{$cfg->{HeaderName}}) {
    	my $subr = $r->lookup_uri($r->uri . $_);
    	my $result = stat $subr->finfo;
    	if ($result) 	{
    			print "<PRE>";
			$subr->run;
       		     	print "</PRE><HR>";
			}
    	else		{
    			$subr = $r->lookup_uri($r->uri . $_ . ".html");
    			$result = stat $subr->finfo;
    			if ($result) {
    				$subr->run;
    				print "<HR>";
    				}
    			}
    	}
	
	print "<TABLE border=0><TR><TH>";
 	my @listing;
 	
	 	if ($args{N} eq 'D'){
 		 @listing = reverse sort $dh->read;
	 	 print "<A HREF=\"?N=A\">Name</A>";
	 	}
	 	else { 
	 	 @listing = sort $dh->read; 
	 	 print "<A HREF=\"?N=D\">Name</A>";
	 	}
 	
 	
 	print "</TH><TH>Last Modified</TH><TH>Size</TH><TH>Description</TH></TR>";
 	
    for my $entry (@listing) {
	foreach (@{$cfg->{IndexIgnore}})
		{
		if ($entry =~ m/^$_$/)
			{
			$entry = '.';
			last;
			}
		}
	next if $entry eq '.';
	my $subr = $r->lookup_file($entry);
	my ($img, $alt);
	stat $subr->finfo;
	my $icon = Apache::Icon->new($subr);
	if($subr->content_type =~ m:^image/:) {
	    #use the image itself for the icon
	    $img = $entry;
	}
	else {
	    	$img = $icon->find;           
	    	if (-d _) {	
			$img ||= $icon->default('^^DIRECTORY^^');	
			$alt = "DIR";
			}	    
		$img ||= $icon->default;
	}
	$alt ||= $icon->alt;               
	
	my $label = $entry eq '..' ? "Parent Directory" : $entry;
	$entry = $entry . "/" if -d _;
	
	print "<TR valign=bottom>";
	print "<TD><img width=20 height=22 src=\"$img\" alt=\"[$alt]\"><a href=\"$entry\">$label</a></TD>";
	print "<TD>" . ht_time((stat _)[9], "%d-%b-%Y %H:%M  ", 0) . "</TD>";
	print "<TD>";
	print -d _ ? "-" : size_string(-s _);
	print "</TD>";
	print "<TD>&nbsp;</TD>";
	print "</TR>\n";	  
    }
	print "</TABLE>\n";
	
	
	foreach (@{$cfg->{ReadmeName}}) {
    	my $subr = $r->lookup_uri($r->uri . $_);
    	my $result = stat $subr->finfo;
    	if ($result) 	{
    			print "<HR><PRE>";
			$subr->run;
       		     	print "</PRE><HR>";
			}
    	else		{
    			$subr = $r->lookup_uri($r->uri . $_ . ".html");
    			$result = stat $subr->finfo;
    			if ($result) {
    				print "<HR>";
    				$subr->run;
    				}
    			}
    	}
	
	
	print " <HR>" . $ENV{'SERVER_SIGNATURE'};
	if ($debug) {
		print "<HR>DUMP<BR><BR><PRE>";
		use Data::Dumper;
		print Dumper $cfg;
		print "</PRE>";
		}
		
	print "</BODY></HTML>";
    return OK
}

	
sub handler {
	my $r = shift;
	return DECLINED unless $r->content_type and $r->content_type eq DIR_MAGIC_TYPE;
	
	my $cfg = Apache::ModuleConfig->get($r);
	$debug = $r->dir_config('AutoIndexDebug') || $debug;
	
	unless ($r->path_info) {
	my $uri = $r->uri;
	$r->header_out(Location => "$uri/");
	$nRedir++;
	return REDIRECT;	
	}   
    
    foreach (@{$cfg->{DirectoryIndex}}) {
    	my $subr = $r->lookup_uri($r->uri . $_);
    	my $result = stat $subr->finfo;
    	if ($result) {
    		     $nIndex++;
    		     return $r->internal_redirect($subr->uri);
       		     }
    	}
    
    
    if($r->allow_options & OPT_INDEXES) {
	return dir_index($r);
    }
    else {
	$r->log_reason( __PACKAGE__ . " Directory index forbidden by rule", $r->uri . " (" . $r->filename . ")");
	return FORBIDDEN;
    }
	
	
	
}


	

sub status {
	my ($r, $q) = @_;
	my @s;
	use Data::Dumper;
	my $cfg = Apache::ModuleConfig->get($r);
	push (@s, "<B>" , __PACKAGE__ , " (ver $VERSION) statistics</B><BR>");

	push (@s , "Done " . $nDir . " listings so far<BR>");
	push (@s , "Done " . $nRedir . " redirects so far<BR>");
	push (@s , "Done " . $nIndex. " indexes so far<BR>");
	#push (@s, "<BR><BR><B>Configuration Directives</B><HR>");
	#push (@s , "<TABLE BORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TH>Directive</TH><TH>Value(s)</TH></TR>");
	#for my $directive (keys %{$cfg}) {
	#push (@s, "<TR><TD><BIG>$directive</BIG></TD><TD>&nbsp;</TD></TR>\n");
	#foreach (@{$cfg->{$directive}}) {
	#	push (@s, "<TR><TD>&nbsp;</TD><TD>$_\n</TD></TR>");
	#	}
	#}
	#push (@s , "</TABLE>");
	
	my $dump = Dumper $cfg;
	push (@s, "<BR><HR><B>Dump of \$cfg object</B><PRE>" . $dump);
	push (@s, "</PRE>");
	return \@s;
	}

1;
__END__

=head1 NAME

Apache::AutoIndex - Perl replacment for mod_autoindex and mod_dir Apache module

=head1 SYNOPSIS

  PerlModule Apache::Icon
  PerlModule Apache::AutoIndex
  PerlHandler Apache::AutoIndex

=head1 DESCRIPTION

This module can replace completely mod_dir and mod_autoindex standard directory handling modules shipped with apache.
It can currently live right on top of those modules.  But it also works if they are not even compiled in.

To start using it on your site right away, simply preload Apache::Icon and Apache::AutoIndex
either with:

  PerlModule Apache::Icon
  PerlModule Apache::AutoIndex

in your httpd.conf file or with:

   use Apache::Icon ();
   use Apache::AutoIndex;
 
in your require.pl file.

Then it's simply adding PerlHandler Apache::AutoIndex somewhere in your httpd.conf but outside any
Location/Directory containers.

It uses most of the Configuration Directives defined by mod_dir and mod_autoindex.  For more information about those, checkout the Apache Documentation http://www.apache.org/docs/mod/

Most of the Directive documentation comes directly from there.

=head2 SUPPORTED DIRECTIVES

=over

=item DirectoryIndex

This is the same thing as the usual mod_autoindex, some directives are not used yet and the +/- syntax is not working yet.

=item FancyIndexing

IndexOptions FancyIndexing should be used instead.  Currently, it will work also.

=item HeaderName filename [filename]*

You can now add more than one filename to check for.

When indexing the directory /web, the server will first look for
the HTML file /web/HEADER.html and include it if found, otherwise
it will include the plain text file /web/HEADER, if it exists.

=item ReadmeName filename [filename]*

Idem. 

=item IndexIgnore filename [filename]*

The IndexIgnore directive defines a list of files to hide when listing a directory.

=back

=head2 NEW DIRECTIVES

=over

=item PerlSetVar AutoIndexDebug [0|1]

If set to 1, the listing displayed will print usefull debugging information appended to the bottom. The default is 0.

=back

=head2 UNSUPPORTED DIRECTIVES

 AddDescription
 FancyIndexing and IndexOptions FancyIndexing
 IndexOrderDefault
 IconHeights[=pixels]
 IconWidth[=pixels]
 IconsAreLinks
 NameWidth[=n|*]
 ScanHTMLTitles
 SuppressColumnSorting
 SuppressDescription
*SuppressHTMLPreamble
 SuppressLastModified
 SuppressSize
 

=head1 TODO

Correct the bug that prevents using Apache::AutoIndex in <Location><Directory> context.

IndexOptions +/- inheritance.

Merging configuration directives should work in vhost/dir/location etc.

Add new configuration directives.
 

=head1 SEE ALSO

perl(1), L<Apache>(3), L<Apache::Icon>(3).

=head1 SUPPORT

Please send any questions or comments to the Apache modperl mailing list <modperl@apache.org> or to me at <gozer@ectoplasm.dyndns.com>

=head1 AUTHOR

Philippe M. Chiasson <gozer@ectoplasm.dyndns.com>

=head1 COPYRIGHT

Copyright (c) 1999 Philippe M. Chiasson. All rights reserved. This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself. 


=cut
