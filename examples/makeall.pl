#!/usr/bin/perl
use OpenGL;
use OpenGL::Script;
use strict;

opendir(DIR,'.');
foreach my $file (grep(/\.ogl$/,readdir(DIR))) {
	print STDERR "$file";
	my $script=OpenGL::Script->new();
	$script->Load($file);
	my $image=$file;
	$image=~s/\.ogl$/\.jpg/;
#	$script->setOption('width',120);$script->setOption('height',120);
	$script->Init({offScreen=>1,
								 imageFile=>$image});
	$script->Run();
	#$script->WriteJpeg('example.jpg')
	$script->Deinit();
	print STDERR "\n";
}
closedir(DIR);
