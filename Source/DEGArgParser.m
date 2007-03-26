/**
 * DEGArgParser.m
 * qtplay
 *
 * Created on 06-09-11.
 *
 * Copyright (c) 2006, Ritchie Argue
 *
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * ¥   Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 * ¥   Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 * ¥   Neither the name of the <ORGANIZATION> nor the names of its contributors
 * may be used to endorse or promote products derived from this software
 * without specific prior written permission.
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

#import "DEGArgParser.h"

// build argtable universal: http://developer.apple.com/technotes/tn2005/tn2137.html
// note that xcode is a broken piece of crap, and will try to link against a
// dylib even if we specify that we want libargtable2.a in the external libs
// section of the project. delete the dylibs to work around this problem.
#import <argtable2.h>															
#import "NSString_Digest.h"
#import "NSPrintf.h"
#import "consts.h"
#import <QTKit/QTKit.h>


// local consts ----------------+---------------+----------------------------
const unsigned int				kAudioCDFilesystemID	= 19016;				// 'JH'
const CFStringRef				kBundleIdentifier = CFSTR("com.doequalsglory.qtplay");


@interface DEGArgParser (ForwardDecls)
+(void) setupDefaultsWithRestore:(BOOL) restore;
-(BOOL) parseArgc:(int) argc argv:(const char **) argv;
-(void) add:(NSURL *) url;
-(void) addFile:(NSURL *) url;
-(void) addPlaylistFile:(NSURL *) url;
-(void) addCDContents;
-(void) addDirectory:(NSURL *) url;
@end


@implementation DEGArgParser

+(void)
initialize {
	[DEGArgParser setupDefaultsWithRestore:NO];
}


/*!
    @method     setupDefaultsWithRestore
    @abstract   restore forces defaults
    @discussion CFPreferences doesn't have a merge or restore to defaults
				feature, so we have to do it manually
*/
+(void)
setupDefaultsWithRestore:(BOOL) restore {
	// CFPreferences doesn't have a merge
	NSArray *keys = (NSArray *) CFPreferencesCopyKeyList(kBundleIdentifier,
														 kCFPreferencesCurrentUser,
														 kCFPreferencesAnyHost);	// for some reason we have to use AnyHost instead of CurrentHost
	
	if (restore) {																// wipe all current values
		CFPreferencesSetMultiple(NULL,
								 (CFArrayRef) keys,
								 kBundleIdentifier,
								 kCFPreferencesCurrentUser,
								 kCFPreferencesAnyHost);
	}
	
	if (restore || ![keys containsObject:@"dbltime"]) {
		double dblTime = (double) GetDblTime() / 60.0;							// GetDblTime returns ticks, 60 ticks/s
		CFPreferencesSetAppValue(
			CFSTR("dbltime"),	[NSNumber numberWithDouble:dblTime],
			kBundleIdentifier);
	}
	if (restore || ![keys containsObject:@"volume"]) {
		CFPreferencesSetAppValue(
			CFSTR("volume"),	[NSNumber numberWithFloat:1.0],					// 100% = 1.0
			kBundleIdentifier);
	}
	
	// write to disk
	CFPreferencesAppSynchronize(kBundleIdentifier);
	
	CFRelease(keys);
}


#pragma mark -

-(id)
initWithArgc:(int) argc argv:(const char **) argv {
	self = [super init];
	if (self != nil) {
		// read from disk
		CFPreferencesAppSynchronize(kBundleIdentifier);
		
		// set up defaults
		NSArray *keys = (NSArray *) CFPreferencesCopyKeyList(kBundleIdentifier,
												   kCFPreferencesCurrentUser,
												   kCFPreferencesAnyHost);		// for some reason we have to use AnyHost instead of CurrentHost
												   
		NSDictionary *prefs = (NSDictionary *) CFPreferencesCopyMultiple((CFArrayRef) keys,
													   kBundleIdentifier,
													   kCFPreferencesCurrentUser,
													   kCFPreferencesAnyHost);
													   
		args = [prefs mutableCopy];
		[prefs release];
		[keys release];
		
		URLs = [[NSMutableArray alloc] init];
		
		if ([self parseArgc:argc argv:argv] == NO) {
			[self release];
			return nil;
		}
	}
	return self;
}


-(void)
dealloc {
	[args release];
	[URLs release];
	
	[super dealloc];
}


-(BOOL)
parseArgc:(int) argc argv:(const char **) argv {
	BOOL						exitcode		= NO;							// default to failure
	
	// we get -- for free
	struct arg_lit * argCD			= arg_litn("cd", "cd,CD", 0, 2,	"play all CDs (backward compatible with -cd)");	// hack to maintain backward compat w/ -cd, 
																													// means we can't use -d on it's own in the future
	struct arg_file * argPlaylists	= arg_filen("f", NULL, "<playlist>", 0, argc + 2,	"treat contents of file(s) as if on command line");
	struct arg_rem * remPlaylists0	= arg_rem(NULL,					" (ie. as playlist)");
	struct arg_rem * remBlank0		= arg_rem(NULL,					"");
	
	struct arg_lit * argVerbose		= arg_lit0("v", "verbose",		"verbose output");
	struct arg_lit * argQuiet		= arg_lit0("q", "quiet",		"quiet");
	struct arg_lit * argSpeak		= arg_lit0("s", "speak",		"DJ mode (ie. speak filename)");
	struct arg_lit * argRecursive	= arg_lit0("r", "recursive",	"evaluate directories recursively");
	struct arg_lit * argShuffle		= arg_lit0("z", "shuffle",		"shuffle play");
	struct arg_lit * argRandom		= arg_lit0("Z", "random",		"random play. equivalent to shuffle + loop");
	struct arg_lit * argLoop		= arg_lit0("l", "loop",			"loop");
	struct arg_lit * argOnlyOne		= arg_lit0("1", NULL,			"one random file");
	//struct arg_lit * argTextfile	= arg_lit0("F", NULL,			"treat found textfiles as a playlist");
	//struct arg_lit * argExpand		= arg_lit0("e", "expand",		"expand CDs, playlists and directories before adding");
	struct arg_rem * remBlank1		= arg_rem(NULL,					"");
	
	struct arg_lit * argQTOnly		= arg_lit0("Q", "quicktime",	"deprecated. switch included for backward compat.");
	struct arg_lit * argSMOnly		= arg_lit0("S", "soundmanager",	"deprecated. switch included for backward compat.");
	struct arg_rem * remBlank2		= arg_rem(NULL,					"");
	
	struct arg_dbl * argDblTime		= arg_dbl0("T", "killtime", "<n>", "kill time (in seconds; default = double click time)");
	struct arg_dbl * argSleepTime	= arg_dbl0("t", "updatetime", "<n>", "deprecated. switch included for backward compat.");
	struct arg_int * argVolume		= arg_int0("V", "volume", "<n>", "volume (in percent; default = 100)");
	struct arg_rem * remBlank3		= arg_rem(NULL,					"");
	
	struct arg_str * argName		= arg_str0("n", "name", "name", "last.fm username");
	struct arg_str * argPassword	= arg_str0("p", "password", "password", "last.fm password");
	struct arg_rem * remBlank4		= arg_rem(NULL,					"");
	
	struct arg_lit * argStorePrefs	= arg_lit0(NULL, "savePrefs",	"save settings to preference file and exit");
	struct arg_lit * argResetPrefs	= arg_lit0(NULL, "resetPrefs",	"reset preferences to default values and exit");
	struct arg_rem * remBlank5		= arg_rem(NULL,					"");
	
	struct arg_lit * argHelp		= arg_lit0("h",	"help",			"display this help and exit");
	struct arg_lit * argVersion		= arg_lit0(NULL, "version",		"print version information and exit");
	struct arg_rem * remBlank6		= arg_rem(NULL,					"");
	
	struct arg_file * argFiles		= arg_filen(NULL, NULL, "<audiofile>,<dir>", 0, argc + 2, "audio files or directories");	// why + 2 and not + 1?
	struct arg_end * argEnd			= arg_end(20);
	
	void * argtable[] = {
						argCD,
						argPlaylists,
						remPlaylists0,
						remBlank0,
						
						argVerbose,
						argQuiet,
						argSpeak,
						argRecursive,
						argShuffle,
						argRandom,
						argLoop,
						argOnlyOne,
						//argTextfile,
						//argExpand,
						remBlank1,
						
						argQTOnly,
						argSMOnly,
						remBlank2,
						
						argDblTime,
						argSleepTime,
						argVolume,
						remBlank3,
						
						argName,
						argPassword,
						remBlank4,
						
						argStorePrefs,
						argResetPrefs,
						remBlank5,
						
						argHelp,
						argVersion,
						remBlank6,
						
						argFiles,
						argEnd
						};
	
	if (arg_nullcheck(argtable) != 0) {
		NSPrintf(@"error: insufficient memory to allocate argtable");
		goto exit;
	}
		
	int nerrors = arg_parse(argc, (char **) argv, argtable);
	
	// special case: '--help' takes precendence over error reporting
	if (argHelp->count > 0) {
		
		NSPrintf(@"Usage: %s [OPTION] [-cd] [<audiofile> | <directory> | -]...\n\n", kStrProgName);
		
		NSPrintf(@"play CDs, audio files, playlists, and directories containing audio");
		NSPrintf(@"files (plays current directory contents by default).");
		NSPrintf(@"if -cd, -f and <audiofile> options are present simultaneously, they");
		NSPrintf(@"will be played in that order, regardless of the command-line ordering.");
		NSPrintf(@"");
		
		arg_print_glossary(stdout, argtable, "  %-26s%s\n");
		
		NSPrintf(@"");
		NSPrintf(@"  %-26s%@", "-", @"read standard input");
		NSPrintf(@"");
		NSPrintf(@"  %-26s%@", "--", @"treat remaining arguments as file names even");
		NSPrintf(@"  %-26s%@", "", @"if they begin with a dash");

		goto exit;
	}
	
	// special case: '--version' takes precedence over error reporting
	if (argVersion->count > 0) {
		NSPrintf(kVersionFormat, kVersionMajor, kVersionMinor, kVersionRevision, kVersionStatus, kVersionEncoding);
		goto exit;
	}
	
	// if the parser returned any errors then display them and exit
	if (nerrors > 0) {
		arg_print_errors(stdout, argEnd, kStrProgName);							// should this be argv[0]?
		NSPrintf(@"Try '%s --help' for more information.", kStrProgName);		// should this be argv[0]?
		
		goto exit;
	}
	
	// if we get here, parsing is ok
	// do our own multi-syntax check: sanity check switches.
	if ((argVerbose->count > 0) && (argQuiet->count > 0)) {
		NSPrintf(@"verbose && quiet doesn't make sense");
		goto exit;
	}
	if ((argOnlyOne->count > 0) && ((argShuffle->count > 0) || (argRandom->count > 0))) {
		NSPrintf(@"onlyone && (shuffle || random) doesn't make sense");
		goto exit;
	}

	// copy parser results into args dictionary
	// override any defaults with the values for this invocation
	if (argRecursive->count > 0) {												// -r
		[args setRecursive:YES];
	}
	if (argVerbose->count > 0) {												// -v
		[args setVerbose:YES];
		[args setQuiet:NO];
	}
	if (argQuiet->count > 0) {													// -q
		[args setVerbose:NO];
		[args setQuiet:YES];
	}
	if (argSpeak->count > 0) {													// -s
		[args setValue:[NSNumber numberWithBool:YES] forKey:@"speak"];
	}
	if (argShuffle->count > 0) {												// -z
		[args setShuffle:YES];
		[args setOnlyOne:NO];
	}
	if (argRandom->count > 0) {													// -Z	random is shuffle + loop
		[args setShuffle:YES];
		[args setLoop:YES];
		[args setOnlyOne:NO];
	}
	if (argLoop->count > 0) {													// -l
		[args setLoop:YES];
	}
	if (argOnlyOne->count > 0) {												// -1
		[args setShuffle:YES];
		[args setOnlyOne:YES];
	}
//	if (argTextfile->count > 0) {												// -F
//		// treat found text files as playlists,
//		// else ignore
//		[args setValue:[NSNumber numberWithBool:YES] forKey:@"textfile"];
//	}
//	if (argExpand->count > 0) {													// -e
//		[args setValue:[NSNumber numberWithBool:YES] forKey:@"expand"];
//	}
	if (argQTOnly->count > 0) {													// -Q
		NSPrintf(@"-Q deprecated. switch included for backward compat.");
	}
	if (argSMOnly->count > 0) {													// -S
		NSPrintf(@"-S is deprecated. SoundManager is no longer supported.");
	}
	if (argDblTime->count > 0) {												// -T
		[args setDblTime:argDblTime->dval[0]];
	}
	if (argVolume->count > 0) {													// -V
		float volume = (float) argVolume->ival[0] / 100;
		volume = MAX(0.0, volume);												// clamp
		volume = MIN(1.0, volume);
		[args setVolume:volume];												// 1.0 == 100%
	}
	if (argName->count > 0) {													// -n --name
		// only take the first name
		[args setValue:[NSString stringWithUTF8String:argName->sval[0]] forKey:@"name"];
	}
	if (argPassword->count > 0) {												// -p --password
		NSString *password = [NSString stringWithUTF8String:argPassword->sval[0]];
		[args setValue:[password md5Digest] forKey:@"password"];
	}
	if (argStorePrefs->count > 0) {												// --savePrefs
		// save args out to defaults
		NSPrintf(@"saving current settings");
		
		CFPreferencesSetMultiple((CFDictionaryRef) args, NULL, kBundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		// write to disk
		CFPreferencesAppSynchronize(kBundleIdentifier);
		
		goto exit;
	}
	
	if (argResetPrefs->count > 0) {												// --resetPrefs
		NSPrintf(@"resetting preferences to default values");
		[DEGArgParser setupDefaultsWithRestore:YES];
		
		// reload args from defaults
		CFArrayRef keys = CFPreferencesCopyKeyList(kBundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		args = (NSMutableDictionary *) CFPreferencesCopyMultiple(keys, kBundleIdentifier, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
		CFRelease(keys);
		
		goto exit;
	}
	
	
	if (argCD->count > 0) {														// -cd: load cd into playlist
		[self addCDContents];
	}
	
	{																			// -f: expand and load playlists into playlist
		int i;																	// this block will pass network files to addPlaylistFile,
		if ([args verbose])														// in case we ever support them there
			NSPrintf(@"argtable # playlists: %d", argPlaylists->count);
			
		for (i = 0; i < argPlaylists->count; i++) {
			if ([args verbose])
				NSPrintf(@"argtable playlist[%d]: %s", i, argPlaylists->filename[i]);
			
			NSString *pathString = [[NSString alloc] initWithCString:argPlaylists->filename[i] encoding:NSUTF8StringEncoding];
			NSURL *path = [[NSURL alloc] initWithString:pathString];
			
			if ([path scheme]) {
				// good to go as-is
			} else {
				if ([args verbose])
					NSPrintf(@"no scheme, assuming file: %@", pathString);
					
				[path release];
				path = [[NSURL alloc] initFileURLWithPath:pathString];
			}

			[self addPlaylistFile:path];										
			
			[path release];
			[pathString release];
		}
	}
	
	{																			// load audio files, directories, stdin
		int i;
		
		if ([args verbose]) {
			NSPrintf(@"argtable # files: %d", argFiles->count);
		}
		
		for (i = 0; i < argFiles->count; i++) {
			if ([args verbose]) {
				NSPrintf(@"argtable file[%d]: %s", i, argFiles->filename[i]);
			}
			
			// don't add as directories (i.e. trailing slash)
			NSString *pathString = [[NSString alloc] initWithCString:argFiles->filename[i] encoding:NSUTF8StringEncoding];
			NSURL *url = [[NSURL alloc] initWithString:pathString];
			
			if ([url scheme]) {
				// good to go as-is
			} else {
				if ([args verbose]) {
					NSPrintf(@"assuming file scheme %@", pathString);
				}
				
				[url release];
				url = [[NSURL alloc] initFileURLWithPath:pathString];
			}
			
			
			[self add:url];													
			
			[url release];
			[pathString release];
		}
	}
	
	if ((argCD->count == 0) &&													// load files in current dir
		(argPlaylists->count == 0) &&
		(argFiles->count == 0)) {
		if ([args verbose]) {
			NSPrintf(@"no arguments, loading files in current directory");
		}
		
		NSURL *path = [[NSURL alloc] initFileURLWithPath:@"."];
		[self add:path];
		[path release];
	}

	if ([args verbose]) {
		NSPrintf(@"finished processing command line options\n\n");
	}
		
	// success
	exitcode = YES;
	
exit:
	arg_freetable(argtable, sizeof(argtable) / sizeof(argtable[0]));

	return exitcode;
}


-(void)
add:(NSURL *) url {
	if (![url isFileURL]) {														// network file
		[self addFile:url];
		return;
	}
	
	if ([[url relativeString] isEqualToString:@"-"]) {							// stdin
		NSPrintf(@"stdin not yet supported");
		return;
	}
	
																				
	FSRef fsRef;																// by here we've got a local file, playlist, or directory
	if ( !CFURLGetFSRef((CFURLRef) url, &fsRef) ) {
		NSPrintf(@"error, file does not exist: %@", url);
		return;
	}
	
	OSErr theErr;
	Boolean isDir;
	Boolean wasAlias;
	theErr = FSResolveAliasFileWithMountFlags(&fsRef, true, &isDir, &wasAlias, kResolveAliasFileNoUI);

	if (theErr == noErr) {
		if (wasAlias) {
			if ([args verbose]) {
				//NSPrintf(@"     resolving alias %@", [url absoluteString]);	// this is asking for a whole world of pain for some reason
				//NSPrintf(@"     resolving alias %@", [url relativeString]);	// this works fine
				NSPrintf(@"     resolving alias %@", url);						// this also works fine
			}
			
			[url release];
			url = (NSURL *) CFURLCreateFromFSRef(NULL /* allocator */, &fsRef);
			
			if ([args verbose]) {
				NSPrintf(@"                  -> %@", [url absoluteString]);
			}
		}

		// if a directory, add contents, else add file
		if (isDir) {
			[self addDirectory:url];
		} else {
			[self addFile:url];
		}
	}
}


/*!
    @method     addFile
    @abstract   (brief description)
    @discussion add a file, we don't care if local or remote. we do care if it's
				a playlist however. remove files that pass the CanQuicktimeOpen
				test, but are playlists. intersect [QTMovie movieFileTypes] with
				the list of playlist formats here:
				http://gonze.com/playlists/playlist-format-survey.html
*/
-(void)
addFile:(NSURL *) url {	

	OSErr err;
	Handle dataRef;
	dataRef = NewHandle(sizeof(AliasHandle));
	OSType dataRefType;
	
	err = QTNewDataReferenceFromCFURL((CFURLRef) url, 0, &dataRef, &dataRefType);
	
	Boolean canOpenWithGraphicsImporter;
	Boolean canOpenAsMovie;
	UInt32 flags = kQTDontUseDataToFindImporter | kQTDontLookForMovieImporterIfGraphicsImporterFound;
	
	err = CanQuickTimeOpenDataRef(dataRef,
								  dataRefType,
								  &canOpenWithGraphicsImporter,
								  &canOpenAsMovie,
								  nil,
								  flags);
	
	if (canOpenAsMovie && !canOpenWithGraphicsImporter) {						// don't allow still image media
		NSString *urlString = [url relativeString];
		NSString *extension = [urlString pathExtension];
		
		if ([extension caseInsensitiveCompare:@"asx"] == NSOrderedSame ||		// don't allow playlist files here
			[extension caseInsensitiveCompare:@"m3u"] == NSOrderedSame ||
			[extension caseInsensitiveCompare:@"pls"] == NSOrderedSame ||
			[extension caseInsensitiveCompare:@"smil"] == NSOrderedSame ||
			[extension caseInsensitiveCompare:@"wax"] == NSOrderedSame ||
			[extension caseInsensitiveCompare:@"wvx"] == NSOrderedSame) {
			if ([args verbose]) {
				NSPrintf(@" discarding playlist %@", [url relativeString]);
			}
			
		} else {
			if ([args verbose]) {
				NSPrintf(@"         adding file %@", [url relativeString]);
			}
			
			[URLs addObject:url];
		}
	} else {
		if ([args verbose]) {
			NSPrintf(@"     discarding file %@", [url relativeString]);
			//NSPrintf(@"              flags %d %d", canOpenWithGraphicsImporter, canOpenAsMovie);
		}
	}
	
	DisposeHandle(dataRef);
	
}


/*!
    @method     addDirectory:
    @abstract   add directory contents to the playlist
    @discussion continue to use FSRefs, as NSFileManager can't follow aliases
*/
-(void)
addDirectory:(NSURL *) url {
	if ([args verbose]) {
		NSPrintf(@"processing directory %@", url);	
	}
	
	FSRef fsRef;
	
	// get fsRef:
	if ( !CFURLGetFSRef((CFURLRef) url, &fsRef) ) {								// check again, but we did this already in -add:
		return;
	}
	
	OSErr theErr;
	FSIterator iterator;
	ItemCount actualNumFiles;
	FSRef contentFSRef;
	HFSUniStr255 contentName;

	theErr = FSOpenIterator(&fsRef, kFSIterateFlat, &iterator);
	if (theErr != noErr) {
		NSPrintf(@"Error opening iterator for: %@", url);
	}

	// loop through contents of directory?
	while (theErr == noErr) {
		theErr = FSGetCatalogInfoBulk(iterator, 1, &actualNumFiles, NULL, kFSCatInfoNone, NULL, &contentFSRef, NULL, &contentName);

		if (theErr != errFSNoMoreItems && theErr != noErr) {
			NSPrintf(@"Error getting contents of directory. Error %d returned: %@", theErr, url);
			
		} else if ( actualNumFiles > 0 &&
					(contentName.unicode[0]) != (UniChar)('.') ) {				// if exists and not invisible:
					
			NSURL *contentURL;
			Boolean contentIsDir;
			Boolean contentWasAlias;

			contentURL = (NSURL *) CFURLCreateFromFSRef(NULL /*allocator*/, &contentFSRef);
			
			// add file or directory (if not recursive, then do not add directories):
			if ([args recursive]) {
				[self add: contentURL];
			} else {
				theErr = FSResolveAliasFileWithMountFlags(&contentFSRef, true, &contentIsDir, &contentWasAlias, kResolveAliasFileNoUI);

				if (theErr != noErr) {
					NSPrintf(@"Error getting info about file in a directory. Error %d returned: %@", theErr, contentURL);
				} else if (!contentIsDir) {
					[self add: contentURL];
				}
			}
			
			[contentURL release];
		}
	}
	
	theErr = FSCloseIterator(iterator);
	if (theErr != noErr) {
		NSPrintf(@"Error closing iterator: %@", url);
	}

}


/*!
    @method     addPlaylistFile:
    @abstract   (brief description)
    @discussion expand m3u file manually. if QTKit handles, there is no
				provision for changing tracks or extracting id3 info
				
				only support m3u for now
*/
-(void)
addPlaylistFile:(NSURL *) url {
	if ([args verbose]) {
		NSPrintf(@"processing playlist file %@", [url absoluteString]);
	}
	
	if (![url isFileURL]) {														// only handle local files for now, stringByDeletingLastPathComponent
		NSPrintf(@"network playlists not yet supported.");						// & friends don't work on urls. wtf.
		
	} else {
		NSString *urlString = [url relativeString];
		NSString *extension = [urlString pathExtension];
		
		if ([extension caseInsensitiveCompare:@"m3u"] != NSOrderedSame) {
			NSPrintf(@"not a recognized playlist format: %@", [url relativeString]);
			
		} else {
			NSError *error;			
			NSString *filelist = [[NSString alloc] initWithContentsOfURL:url encoding:NSISOLatin1StringEncoding error:&error];
			
			if (filelist == nil) {
				NSPrintf(@"couldn't open playlist file: %@", [url relativeString]);
				
			} else {				
				// iterate over filelist
				NSScanner *scanner = [[NSScanner alloc] initWithString:filelist];
				
				// why the hell isn't there a predefined newlineCharacterSet?
				NSMutableCharacterSet *newlineCharacterSet = [[NSCharacterSet whitespaceAndNewlineCharacterSet] mutableCopy];
				NSCharacterSet *notWhitespaceCharacterSet = [[NSCharacterSet whitespaceCharacterSet] invertedSet];
				[newlineCharacterSet formIntersectionWithCharacterSet:notWhitespaceCharacterSet];
				
				NSString *playlistPath = [[url path] stringByDeletingLastPathComponent];
				
				while (![scanner isAtEnd]) {
					NSString *line;
					[scanner scanUpToCharactersFromSet:newlineCharacterSet intoString:&line];
					
					if (![line hasPrefix:@"#"]) {
						NSString *filepath = [playlistPath stringByAppendingPathComponent:line];						
						NSURL *fileurl = [[NSURL alloc] initFileURLWithPath:filepath];
						if ([args verbose]) {
							NSPrintf(@"adding: %@", fileurl);
						}
						
						[URLs addObject:fileurl];
						[fileurl release];
					}
				}
				
				[filelist release];
			}
		}
	}
}


-(void)
addCDContents {
	if ([args verbose]) {
		NSPrintf(@"processing CD(s)");
	}
	
	int							filenum			= 0;
	OSErr						theErr			= noErr;
	FSVolumeInfo				info;
	FSRef						volumeFSRef;
		
	for ( filenum = 1; theErr != nsvErr; filenum++ ) {
		theErr = FSGetVolumeInfo(kFSInvalidVolumeRefNum, filenum, NULL, kFSVolInfoFSInfo, &info, NULL, &volumeFSRef);
		
		if (theErr == noErr) {
			// bug fix from Apple web site example code:
			// Work around a bug in Mac OS X 10.0.x where the filesystem ID and
			// signature bytes were erroneously swapped. This was fixed in Mac OS X 10.1 (r. 2653443).
			long systemVersion;
			if (Gestalt(gestaltSystemVersion, &systemVersion) != noErr) {
				systemVersion = 0;
			}
			
			if ((systemVersion >= 0x00001000 && systemVersion < 0x00001010 && info.signature == kAudioCDFilesystemID)
				|| info.filesystemID == kAudioCDFilesystemID) {
				// volume is an Audio CD, set path. don't strip file://localhost any longer
				CFURLRef path = CFURLCreateFromFSRef(NULL, &volumeFSRef);
				
				if (path != NULL) {
					if ([args verbose])
						NSPrintf(@"getting contents of CD: %@", path);
				
					[self addDirectory:(NSURL *) path];
					
					CFRelease(path);
				}
			}
		} else if (theErr != nsvErr) {
			NSPrintf(@"Error getting information for volume %d. Error %d returned.", filenum, theErr);
		}
	}
}


-(NSDictionary *)
args {
	//return [[args copy] autorelease];
	return args;
}

-(NSArray *)
URLs {
	//return [[URLs copy] autorelease];
	return URLs;
}

@end


@implementation NSDictionary (DEGArgParser)

-(BOOL) verbose { return [[self valueForKey:@"verbose"] boolValue]; }
-(BOOL) quiet { return [[self valueForKey:@"quiet"] boolValue]; }
-(BOOL) recursive { return [[self valueForKey:@"recursive"] boolValue]; }
-(BOOL) shuffle { return [[self valueForKey:@"shuffle"] boolValue]; }
-(BOOL) onlyone { return [[self valueForKey:@"onlyone"] boolValue]; }
-(BOOL) loop { return [[self valueForKey:@"loop"] boolValue]; }
-(float) volume { return [[self valueForKey:@"volume"] floatValue]; }
-(double) dblTime { return [[self valueForKey:@"dbltime"] doubleValue]; }

@end


@implementation NSMutableDictionary (DEGArgParser)

-(void) setVerbose:(BOOL) verbose { [self setValue:[NSNumber numberWithBool:verbose] forKey:@"verbose"]; }
-(void) setQuiet:(BOOL) quiet { [self setValue:[NSNumber numberWithBool:quiet] forKey:@"quiet"]; }
-(void) setRecursive:(BOOL) recursive { [self setValue:[NSNumber numberWithBool:recursive] forKey:@"recursive"]; }
-(void) setShuffle:(BOOL) shuffle { [self setValue:[NSNumber numberWithBool:shuffle] forKey:@"shuffle"]; }
-(void) setOnlyOne:(BOOL) onlyone { [self setValue:[NSNumber numberWithBool:onlyone] forKey:@"onlyone"]; }
-(void) setLoop:(BOOL) loop { [self setValue:[NSNumber numberWithBool:loop] forKey:@"loop"]; }
-(void) setVolume:(float) volume { [self setValue:[NSNumber numberWithFloat:volume] forKey:@"volume"]; }
-(void) setDblTime:(double) dblTime { [self setValue:[NSNumber numberWithDouble:dblTime] forKey:@"dbltime"]; }

@end