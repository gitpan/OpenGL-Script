package OpenGL::Script;
use strict;
use Error qw(:try);
use Time::HiRes qw(gettimeofday tv_interval);
use File::Copy;
use FileHandle;
use OpenGL ':functions', ':constants'; #':osfunctions', ':osconstants';

use vars qw($VERSION %InternalFunc %ErrorMessages);

( $VERSION ) = '$Revision: 0.2 $ ' =~ /\$Revision:\s+([^\s]+)/;

%InternalFunc=(swapBuffers=>'ogls_swapBuffers',
							 foreach=>'ogls_foreach');

%ErrorMessages=(
								1 =>'No such subroutine:',
								2 =>'No such array:',
								3 =>'Invalid internal presentation of operator: ',
								4 =>'Unknown error',
								5 =>'No such function: ',
								6 =>'Wrong loop syntax. Must be "foreach(start,stop)"',
								7 =>'There is no looped function.',
								8 =>'',
								9 =>'Error parse cursor option: ',
								10=>'Error parse subroutine',
								11=>"Can't open file",
								12=>"Error parse option line:",
								13=>'Error parse line:',
								14=>'No image file',
								15=>"Bad name of the image file:",
								16=>"Unknown internal line type: ",
								17=>'',
								18=>'Invalide variable or array set:',
								19=>'',
								20=>'Invalide line number',
								
							 );

@Error::OpenGL::Script::ISA = qw(Error);


=pod TODO

Limit images number

=cut

sub new {
	my ($class)=@_;
	my $self = {options=>{},script=>[]};
	return bless $self, $class;
}

sub error { throw Error::Simple shift; }

sub rtError {
	my ($self,$code,$ext)=@_;
	my $text=$ErrorMessages{$code};
	throw Error::OpenGL::Script -text=>$text,
		-value=>{runtime =>$self->{runtime},
						 type    =>'runtime',
						 code    =>$code,
						 text    =>$text,
						 ext     =>$ext};
}

sub cError {
	my ($self,$code,$sub,$line,$ext)=@_;
	my $text=$ErrorMessages{$code};
	
	my $hr={code    =>$code,
					settime =>{sub => $sub,
										 line=> $line},
					text    =>$text,
					ext     =>$ext};
	if (defined $self->{loadLine}) {
		$hr->{type} = 'loadtime';
		$hr->{loadtime} = {sub => $self->{loadSub},
											 line=> $self->{loadLine}};
	} else {
		$hr->{type}    ='settime';
	}
	throw Error::OpenGL::Script -text=>$text,
		-value=>$hr;
}

sub loadError {
	my ($self,$code,$ext)=@_;
	my $text=$ErrorMessages{$code};
	throw Error::OpenGL::Script -text=>$text,
		-value=>{loadtime =>{sub =>$self->{loadSub},
												 line=>$self->{loadLine}},
						 type    =>'loadtime',
						 code    =>$code,
						 text    =>$text,
						 ext     =>$ext};
}

sub saveError {
	my ($code,$ext)=@_;
	my $text=$ErrorMessages{$code};
	throw Error::OpenGL::Script -text=>$text,
		-value=>{type    =>'savetime',
						 code    =>$code,
						 text    =>$text,
						 ext     =>$ext};
}

sub iError {
	my ($self,$code,$ext)=@_;
	my $text=$ErrorMessages{$code};
	throw Error::OpenGL::Script -text=>$text,
		-value=>{type    =>'write image',
						 code    =>$code,
						 text    =>$text,
						 ext     =>$ext};
}

sub cursor {
	my $self=shift;
	my ($sub,$line)=@_;

	if ($sub=~/./ || $line=~/\d/) {
		$self->{needToSave}=1;
		$sub=$self->cursor()->{sub} unless $sub=~/./;
		$self->cError(1,$sub,$line)
			unless $sub || $self->subExists($sub);
		$line+=0;
		if ($line<0) {
			$line=$self->subExists($sub) ? scalar @{$self->{script}->{$sub}} : 0;
		}
		return $self->{options}->{cursor}="$sub:$line";
	} else {
		$self->{options}->{cursor}='MAIN:-1' unless $self->{options}->{cursor};
		$self->{options}->{cursor}=~/^(\S+):(\S+)$/ || cError(9,$self->{options}->{cursor});
		return {sub=>$1,
						line=>$2};
	}
}

sub setFileName {
	my ($self,$file)=@_;
	return $self->{fileName}=$file;
}

sub getFileName { return shift->{fileName}; }

sub getMTime    { return shift->{mtime};    }
sub getScript   { return shift->{script};   }
sub getOptions  { return shift->{options};  }

sub needToSave  { return shift->{needToSave}; }

sub getOption  {
	my ($self,$key)=@_;
	return $self->{options}->{$key};
}

sub setOption  {
	my ($self,$key,$value)=@_;
	$self->{needToSave}=1;
	return $self->{options}->{$key}=$value;
}

sub Clear {
	my $self=shift;
	$self->{description}=[];
	$self->{script}={};
	$self->{options}={};
	$self->{loadLine}=0;
	$self->{fileName}='';
	$self->{mtime}=0;
	$self->{needToSave}=0;
	$self->{inited}=0;
}

sub subExists {
	my ($self,$sub)=@_;
	return exists $self->{script}->{$sub};
}

sub Init  {
	my ($self,$param)=@_;
	$self->{variables}={};
	$self->{arrays}   ={};
	my @attributes=map { calcParam($_,1) } split(',',$self->{options}->{attributes});
	if ($param->{offScreen}) {
		glosCreateContext($self->{options}->{width},
											$self->{options}->{height});
		$self->{offScreen}=1;
		$self->{imageFile}=$param->{imageFile};
		$self->{imageIndex}=0;
	} else {
		OpenGL::glpOpenWindow(width => $self->{options}->{width}, height => $self->{options}->{height},
													attributes => \@attributes
												 );
		$self->{offScreen}=0;
	}
	$self->{inited}=1;
}

sub Deinit {
	my $self=shift;
	return undef unless $self->{inited};
	if ($self->{offScreen}) {
		$self->WriteJpeg($self->{imageFile})
			if $self->{imageFile} && !$self->{imageIndex};
		glosDestroyContext();
	} else {
		OpenGL::glpMainLoop();
	}
	$self->{inited}=0;
}





##################################################
#
# Load and parse routines
#
##################################################

sub _startSub {
	my ($self,$sub)=@_;
	$self->{loadSub}=$sub;
	$self->loadError(10)
		if $self->{script}->{$sub};
	$self->{script}->{$sub}=[];
}


sub Load {
	my ($self,$file)=@_;
	$self->Clear();
	$self->{fileName}=$file;
	$self->{mtime}=(stat($file))[9];
	$self->{loadSub}=undef;
	my $fh = new FileHandle "< $file";
	$self->loadError(11,$file)
		unless $fh;
	while (<$fh>) {
		chomp;
		$self->{loadLine}++;
		if (/^(\S+):/) {
			$self->_startSub($1);
		} elsif ($self->{loadSub}) {
			$self->{script}->{$self->{loadSub}}=[] unless $self->{script}->{$self->{loadSub}};
			$self->addLine($self->{loadSub},$_);
		} else {
				$self->addOption($_);
			}
	}
	$fh->close();
	$self->{loadLine}=undef;
	$self->{loadSub}=undef;
#	if ($self->subExists('MAIN')) {
#		$self->cursor('MAIN',-1);
#		$self->{needToSave}=0;
	#	}
	$self->{needToSave}=0;
	return 1;
}

sub addLine {
	my ($self,$sub,$line)=@_;
	$self->appendLine($sub,scalar @{$self->{script}->{$sub}},$line);
}

sub addOption {
	my ($self,$line)=@_;
	my $comment = $line=~s/\#(.*)$// ? $1 : undef;
	$line=~s/^\s+//g;
	$line=~s/\s+$//g;
	return unless $line;
	if ($line=~/^([a-z0-9_]+)\s*=\s*(.*)\s*$/i) {
		my ($key,$value)=($1,$2);
		$self->{needToSave}=1;
		$self->{options_desc}->{$key}=$comment if $comment;
		return $self->{options}->{$key}=$value;
	} else {
		$self->loadError(12,$line);
	}
}

sub setCurLine_ {
	my ($self,$line)=@_;
	my $cursor=$self->cursor();
	return
		$self->setLine($cursor->{sub},
									 $cursor->{line}-1,
									 $line);
}

sub deleteCurLine_ {
	my ($self,$line)=@_;
	my $cursor=$self->cursor();
	return
		$self->deleteLine($cursor->{sub},
											$cursor->{line}-1);
}

sub insertCurLine_ {
	my ($self,$line)=@_;
	my $cursor=$self->cursor();
	return
		$self->insertLine($cursor->{sub},
											$cursor->{line}-1,
											$line);
}

sub appendCurLine_ {
	my ($self,$line)=@_;
	my $cursor=$self->cursor();
	return
		$self->appendLine($cursor->{sub},
											$cursor->{line}-1,
											$line);
}

sub deleteLine {
	my ($self,$sub,$num)=@_;
	$self->cError(1,$sub)
		unless $self->{script}->{$sub};
	$self->cError(20,$num,scalar @{$self->{script}->{$sub}})
		if $num<0 || $num>=@{$self->{script}->{$sub}};
	splice(@{$self->{script}->{$sub}},$num,1);
		$self->{needToSave}=1;
	#	my $cursor=$self->cursor();
	#	$self->cursor('',$cursor->{line}-1)
	#		if $cursor->{sub} eq $sub && $cursor->{line}-1>$num;
}

sub insertLine {
	my ($self,$sub,$num,$line)=@_;
	$self->cError(1,$sub)
		unless $self->{script}->{$sub};
	$self->cError(20,$num,scalar @{$self->{script}->{$sub}})
			if $num<0 || $num>=@{$self->{script}->{$sub}};
	$line=$self->parseLine($line)
		unless ref($line)=~/HASH/;
	return undef unless %$line;
	splice(@{$self->{script}->{$sub}},$num,0,$line);
	$self->{needToSave}=1;	
#	my $cursor=$self->cursor();
#	$self->cursor('',$cursor->{line}+1)
#		if $cursor->{sub} eq $sub && $cursor->{line}-1>=$num;
}

sub appendLine {
	my ($self,$sub,$num,$line)=@_;
	$self->cError(1,$sub)
		unless $self->{script}->{$sub};
	$self->cError(20,$num,scalar @{$self->{script}->{$sub}})
		if $num<0 || $num>@{$self->{script}->{$sub}};
	$line=$self->parseLine($line)
		unless ref($line)=~/HASH/;
	return undef unless %$line;
	splice(@{$self->{script}->{$sub}},$num+1,0,$line);
		$self->{needToSave}=1;
#	my $cursor=$self->cursor();
#	$self->cursor('',$cursor->{line}+1)
#		if $cursor->{sub} eq $sub && $cursor->{line}-1>=$num;
}

sub setLine {
 	my ($self,$sub,$num,$line)=@_;
	$self->cError(1,$sub)
		unless $self->{script}->{$sub};
	$self->cError(20,$num,scalar @{$self->{script}->{$sub}})
			if $num<0 || $num>scalar @{$self->{script}->{$sub}};
	$line=$self->parseLine($line)
		unless ref($line)=~/HASH/;
	return undef unless %$line;
	$self->{script}->{$sub}->[$num]=$line;
	$self->{needToSave}=1;
}

sub setSubCode {
	my ($self,$sub,$code)=@_;
		$self->{needToSave}=1;
	my $num=0;
	$self->{script}->{_}=[];
	while ($code=~/(.*)/mg) {
		my $line=$1;
		$line=~s/[\n\r]//g;
		$self->addLine('_',$line)
			if $line;
	}
	$self->{script}->{$sub}=$self->{script}->{_};
	delete $self->{script}->{_};
}

sub deleteSub {
	my ($self,$sub)=@_;
	$self->cError(1,$sub)
		unless $self->{script}->{$sub};
	delete $self->{script}->{$sub};
}

sub parseLine {
	my ($self,$line)=@_;

	my $comment = $line=~s/\#(.*)$// ? $1 : undef;
	$line=~s/^\s+//g;
	$line=~s/\s+$//g;
	$line=~s/\;$//;
	$line=~s/\s+$//g;
	my $pl;
	if (!$line) {
		$pl={};
	} elsif ($line=~/^(.*)\s*\=\s*(.*)$/) {
		$pl=$self->parseSet($1,$2);
	} elsif ($line=~/\=/) {
		$self->cError(13,$line);
	} elsif ($line=~/^([a-z0-9_]+)(\s*\(([^()]*)\))?$/i) {
		$pl=$self->parseFunction($1,$3);
	} else {
		$self->cError(13,$line);
	}
	$comment=~s/^\s+//g;
	$pl->{comment}=$comment if $comment || %$pl;
	
	return $pl;
}

sub parseSet {
	my ($self,$name,$value)=@_;
	$name=~s/\s+$//g;$name=~s/^\s+//g;
	#	$value=~s/\s+//g;
	if ($name=~/^\$([a-z0-9_]+)$/i) {
		return {type =>'set',
						name =>$1,
						value=>$value};
	} elsif ($name=~/^\@([a-z0-9_]+)$/i) {
		$name=$1;
		$value=~s/^\((.*)\)$/$1/;
		$value=~s/\s*,\s*/,/g;
 		return {type =>'set',
						name =>$name,
						list=>[split(',',$value)]};
	} else {
		$self->cError(18,$name,$value);
	}
}

sub parseFunction {
	my ($self,$func,$params)=@_;
	$params=~s/^\((.*)\)$/$1/;
	$params=~s/\s*,\s*/,/g;
	$params=~s/\s*\|\s*/|/g;
	$params=~s/\s*\|\s*/ | /g;
	return {type   => 'func',
					name   => $func,
					params => [split(',',$params)]};
}

##################################################
#
# Run-time routines
#
##################################################



sub Run {
	my $self=shift;
	$self->{imageList}=[];
	$self->{runtime}={};
	return 0 unless $self->subExists('MAIN');
	my $t = [gettimeofday()];
	$self->runSub('MAIN');
	$self->setOption('renderTime',int(tv_interval( $t, [gettimeofday()])*100));
}

sub runSub {
	my $self=shift;
	my $sub=shift;
	my $runtime=$self->{runtime};
	$self->{runtime}={sub=>$sub,
										line=>0};
	$self->rtError(1) unless $self->{script}->{$sub};
	foreach my $i (0..(@_-1)) {
		$self->{variables}->{$i+1}=$_[$i];
	}
	while (my $cmd=$self->getLine($sub,$self->{runtime}->{line})) {
		$self->runCommand($cmd);
		$self->{runtime}->{line}++;
	}
	$self->{runtime}=$runtime;
	return 1;
}

sub getLine {
	my ($self,$sub,$line)=@_;
	return $self->{script}->{$sub}->[$line];
}

sub evalArray {
	my ($self,$name,$index)=@_;
	my $array=$self->{arrays}->{$name};
	$self->rtError(2,$name) unless $array;
	$index=$self->evalVariable($index);
	## !!! Проверить на перепонление массива
	return $array->[$index];
}

sub evalVariable {
	my ($self,$value)=@_;
	$value=~s/\$([a-z0-9_]+)\[(.+)\]/$self->evalArray($1,$2)/ge;
	$value=~s/\$([a-z0-9_]+)/$self->{variables}->{$1}/ge;
	$value=eval($value);
	return $value;
}

sub runCommand {
	my ($self,$command,@params)=@_;
	return $self->runFunc($command,@params)
		if $command->{type} eq 'func';
	
	if ($command->{type} eq 'set') {
		if ($command->{list}) {
			$self->{arrays}->{$command->{name}}=$command->{list};
		} else {
			$self->{variables}->{$command->{name}}=
				$self->evalVariable($command->{value});
		}
	} elsif ($command->{type}) {
		$self->rtError(3,join(',',%$command));
	} elsif ($command->{comment}) {
	} else {
		$self->rtError(4,join(',',%$command));
	}
	return 1;
}

sub calcParam {
	my ($param,$isConst)=@_;
	return eval($param);
}

sub compileParams {
	my ($self,$params)=@_;
	my @p;
	foreach (@$params) {
		if (/^([\@\$\%])([a-z0-9_]+)$/) {
			my ($type,$name)=($1,$2);
			if ($type eq '@') {
				push @p,@{$self->{arrays}->{$name}};
			} elsif ($type eq '%') {
				my $array=$self->{arrays}->{$name};
				push @p, pack("f".scalar @$array,@$array);
			} else {
				push @p,$self->{variables}->{$name};
			}
		} else {
			push @p,calcParam($_);
		}
	}
	return \@p;
}

sub runFunc {
	my ($self,$f)=@_;
	my $params=$self->compileParams($f->{params});
	
	my $func=$f->{name};
#	print  "$func(".join(',',@$params).")\n";
	my $ref=OpenGL->can($func);
	$ref=OpenGL->can("${func}_s") unless $ref;
	if ($ref) {
		&$ref(@$params);
	} elsif ($self->{script}->{$func}) {
		$self->runSub($func,@$params);
	} elsif ($func=$InternalFunc{$func}) {
		$ref=$self->can($func);
		&$ref($self,@$params);
	} else {
		$self->rtError(5,$f->{name});
	}
#	eval &{"OpenGL::$f->{func}"}(@params);
}

sub ogls_foreach {
	my ($self,$start,$end)=@_;
	$self->rtError(6)
		unless defined $start && defined $end;
	my $func=$self->getLine($self->{runtime}->{sub},++$self->{runtime}->{line});
	$self->rtError(7)
		unless $func;
	foreach my $i ($start..$end) {
		$self->{variables}->{_}=$i;
		$self->runFunc($func);
	}
}

sub ogls_swapBuffers {
	my $self=shift;
	if ($self->{offScreen}) {
		my $index=shift;
		if (defined $index) {
			$self->{imageIndex}=$index+1;
		} else {
			$index=$self->{imageIndex}++;
		}
		$self->WriteJpegIndex($self->{imageFile},$index);
	} else {
		OpenGL::glXSwapBuffers();
	}
	return 1;
}


#################################################
#
# Save script
#
#################################################

sub printLine {
	my $h=shift;
	my $line;
	if ($h->{type} eq 'func') {
		$line="$h->{name}(".join(', ',@{$h->{params}}).")";
	} elsif ($h->{type} eq 'set') {
		$line=$h->{list}
			?	"\@$h->{name} = (".join(', ',@{$h->{list}}).")"
				:	"\$$h->{name} = $h->{value}";
	} elsif (!$h->{comment}) {
		saveError(16,$h->{type});
	}
	$line=$line ? "$line # $h->{comment}" : "# $h->{comment}"
		if $h->{comment};
	return $line;
}


sub Save {
	my ($self,$file)=@_;
	$file=$self->{fileName} unless $file;
	my $backup="$file.bak";
	
	copy($file,$backup);
	
	$self->{fh} = new FileHandle "> $file";

	foreach (keys %{$self->{options}}) {
		$self->{fh}->print(" $_\t= $self->{options}->{$_}\n");
	}

	foreach my $sub (sort keys %{$self->{script}}) {
		$self->saveSub($sub);
	}
	$self->{fh}->close();
	$self->{mtime}=(stat($file))[9];
	$self->{needToSave}=0;
	delete $self->{fh};
}

sub saveSub {
	my ($self,$sub)=@_;
	$self->{fh}->print("\n$sub:\n");
	my $last;
	foreach (@{$self->{script}->{$sub}}) {
		my $cur=$_->{type} eq 'func' ? $_->{name} : '';
		my $ident=$cur eq 'foreach' || $last eq 'foreach' ? "   " : " ";
		$self->{fh}->print($ident.printLine($_)."\n");
		$last=$cur;
	}
}


#################################################
#
# Image routines
#
#################################################


sub getImageList {
	my $self=shift;
	return $self->{imageList};
}

sub WriteJpegIndex {
	my ($self,$file,$index)=@_;
	iError(14) unless $file;
	iError(15,$file) unless $file=~s/^(.*)(\.jpeg|\.jpg)$/$1$index$2/;
	push @{$self->{imageList}},$file;
	$self->WriteJpeg($file);
}

sub WriteJpeg {
	my ($self,$file)=@_;
	iError(15,$file) if $file eq $self->{fileName};
	OpenGL::glosWriteJpeg($file);
}

1;
