BEGIN { print "1..1\n" }

eval { require OpenGL::Script };
if ( $@ ) {
 print "not ";
}
print "ok\n";
