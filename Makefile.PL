require 5.004;
use ExtUtils::MakeMaker;
use ExtUtils::Manifest qw(maniread);

ExtUtils::Manifest::mkmanifest;

unlink 'MANIFEST.bak' if -f 'MANIFEST.bak';
unlink 'Makefile.old' if -f 'Makefile.old';

sub MY::libscan
	{
		my($self,$path) = @_;

		return '' 
			if ($path =~ m:/(RCS|CVS|SCCS)/: ||
					$path =~ m:[~%.]$: ||
					$path =~ m:\.(orig|rej|nfs)$:
				 );
		
		$path;
	}

#sub MY::post_initialize	{"";	}


WriteMakefile(
							NAME	       => 'OpenGL::Script',
							VERSION_FROM => './Script.pm',
							AUTHOR       => 'Danil Pismenny <dapi@mail.ru>',
							ABSTRACT     => 'OpenGL scripting',
#							PMLIBDIRS    => [ 'lib', '$(BASEEXT)', 'awe' ],
							PREREQ_PM    => {
															 'OpenGL'           => 0.54,
															 'Time::HiRes'      => 1.20,
															 'Error'            => 0.15,
															},
							
							dist => {COMPRESS=>'bzip2', SUFFIX=>'bz2'},
							clean => {FILES=>'*.bz2*'}
						 );
