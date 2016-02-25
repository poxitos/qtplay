# Introduction #

Linking qtplay with argtable is tricky due to a bug in XCode and the way autoconf-based projects are built as Universals. Although the project specifies libargtable2.a as the library to link against, XCode tries to link against libargtable2.dylib. This can cause problems when building a Universal binary of qtplay.

# Details #

Begin by building a Universal Binary of [argtable](http://argtable.sourceforge.net/). This is done by following the instructions in [tech note 2137](http://developer.apple.com/technotes/tn2005/tn2137.html). Roughly:

```
setenv CFLAGS "-O -g -isysroot /Developer/SDKs/MacOSX10.4u.sdk -arch ppc -arch i386"
setenv LDFLAGS "-arch ppc -arch i386"
./configure --disable-dependency-tracking
sudo make install
```

On my machine, this builds a Universal static lib (libargtable2.a), but the libargtable2.dylib is single architecture. I'm not sure why this is. If qtplay is built at this point, XCode will complain that it can't link against argtable for the i386 version. This is because it is looking in the dylib. Either delete the dylib, or don't build it in the first place.

```
sudo rm /usr/local/lib/libargtable2*.dylib
```

Now a Universal build of qtplay should work.