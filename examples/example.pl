#!/usr/bin/perl
use lib qw(..);
use OpenGL::Script;

my $script=OpenGL::Script->new();


$script->Load($ARGV[0]);
#$script->setOption('width',100);
#$script->setOption('height',120);
#print join(',',%{$script})."\n";
#$script->Save('test.ogl');
print "\n";
#print join(',',%{$script})."\n";
$script->Init({offScreen=>1,
							 imageFile=>'example.jpg'});
$script->Run();
$script->WriteJpeg('example.jpg');
$script->Deinit();

