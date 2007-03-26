/**
 * DEGAudioScrobbler.m
 * qtplay
 *
 * Created on 06-09-13.
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

#import "DEGAudioScrobbler.h"

#import "NSPrintf.h"
#import "NSString_Digest.h"
#import "NSString_FourCharCode.h"
#import "NSString_URIEncode.h"
#import "QTMovie_Metadata.h"


@implementation DEGAudioScrobbler

-(id)
initWithName:(NSString *) aName password:(NSString *) aPassword {
	if (aName && aPassword) {
		self = [super init];
		if (self) {
			username = [aName copy];
			password = [aPassword copy];
			
			md5Response = [[NSString alloc] init];
			submissionURL = [[NSURL alloc] init];
			
			// man the 10.4+ icu date formatting is gross
			[NSDateFormatter setDefaultFormatterBehavior:NSDateFormatterBehavior10_4];
			dateFormatter = [[NSDateFormatter alloc] init];
			[dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
			[dateFormatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"GMT"]];
	
			usernameInvalid = NO;
			handshakeCompleted = NO;
			failureCount = 0;
		}
	} else {
		self = nil;
	}
	return self;
}


/*!
    @method     dealloc
    @abstract   <#brief description#>
    @discussion should we recache sent items here, just incase we get shut down
				mid-send? ideally we should postpone shutdown until a send
				completes (or times out). what's the best way to do that?
*/
-(void)
dealloc {
	[dateFormatter release];
	[submissionURL release];
	[md5Response release];
	[password release];
	[username release];
	
	[super dealloc];
}


/*!
    @method     pathForDataFile
    @abstract   (brief description)
    @discussion there should be an object similar to NSUserDefaults/CFPrefs
				to deal with the Application Support folder
*/
-(NSString *)
pathForDataFile {
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSString *folder = @"~/Library/Application Support/qtplay/";
	folder = [folder stringByExpandingTildeInPath];
	
	if ([fileManager fileExistsAtPath:folder] == NO) {
		[fileManager createDirectoryAtPath:folder attributes:nil];
	}
	
	NSString *fileName = @"audioscrobbler.cache";
	return [folder stringByAppendingPathComponent: fileName];
}


#pragma mark -
/*!
    @method     submit:
    @abstract   entry point for data submission
    @discussion	however, submit is now only called when it is possible to
				receive movieDidEnd notifications, so we should be sure to
				be notified of unloads?
				no. we need to submit before movieLoadStateComplete, in case we
				receive seek notifications. the player is now responsible for
				unloading as well
*/
-(void)
submit:(QTMovie *) aMovie {
	if ([aMovie durationInSeconds] < 30) {										// audioscrobbler spec: songs must be at least 30s long
		return;
	}
	
	movie = [aMovie retain];
	
	//NSTimeInterval postTime = 5;
	NSTimeInterval postTime = MIN(240, [movie durationInSeconds] / 2);			// audioscrobbler spec: post in 240s or duration / 2, whichever comes first
	[self performSelector:@selector(addToCache) withObject:nil afterDelay:postTime];
	
																				// except if the movie is seeked before then
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(seek:) name:QTMovieTimeDidChangeNotification object:movie];
}


/*!
    @method     seek:
    @abstract   handle QTMovieTimeDidChangeNotification
    @discussion cancel post timer
*/
-(void)
seek:(NSNotification *) aNotification {
	//NSPrintf(@"scrobbler seek'd");
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(addToCache) object:nil];
}


-(void)
releaseMovie {	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:QTMovieTimeDidChangeNotification object:movie];
	
	// if the movie ends before the timer fires (i.e. due to next track selection), remove the timer
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(addToCache) object:nil];
	
	[movie release];
}


#pragma mark -
/*!
    @method     handshake
    @abstract   (brief description)
    @discussion username is assumed ok from the start. if we get a BADUSER
				response, set a flag, let the user know, and don't try to
				handshake again until the next invocation (maybe username has
				changed by then)
*/
-(void)
handshake {
	// if receivedData is defined, we are in the process of a network transfer
	// already so don't start a new one
	if (usernameInvalid == NO && receivedData == nil) {
		NSString *handshakeURL = [NSString stringWithFormat:
			@"http://post.audioscrobbler.com/?hs=true&p=1.1&c=%@&v=%@&u=%@",
			@"qtp",																// player name granted by http://www.last.fm/user/Russ/
			@"0.1",																// player vers granted by http://www.last.fm/user/Russ/
			username];
		
		NSURLRequest *theRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:handshakeURL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10];
		NSURLConnection *theConnection = [[NSURLConnection alloc] initWithRequest:theRequest delegate:self];
		if (theConnection) {
			receivedData = [[NSMutableData alloc] init];
		} else {
			// couldn't make the connection
		}
	}
}


/*!
    @method     flushCache
    @abstract   wait interval seconds, and then actually flush
    @discussion it'd be nice to check if we're scheduled to flush, and not
				bother to schedule a new flush. however, NSTimers have their
				own problems with determining invalidation or release and
				this seems easier to deal with
				
				test failure count, and don't bother flushing if we've had
				more than a few failures? or re-handshake?
*/
-(void)
flushCache {
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flushCacheNow) object:nil];
	[self performSelector:@selector(flushCacheNow) withObject:nil afterDelay:interval];
}


/*!
    @method     flushCacheNow
    @abstract   (brief description)
    @discussion each submission must be both utf8 and percent encoded. it seems
				that the percent encoding is only necessary to handle ampersands
				in the submission string, but it doesn't seem to hurt to percent
				escape everything else as well
*/
-(void)
flushCacheNow {
	// if receivedData is defined, we are in the process of a network transfer
	// already so don't start a new one. set a timer to fire a new one?
	if (receivedData == nil) {
		// get cache
		NSDictionary *rootObject = [NSKeyedUnarchiver unarchiveObjectWithFile:[self pathForDataFile]];
		NSArray *pendingEntries = [rootObject valueForKey:@"pendingEntries"];
		
		if ([pendingEntries count] > 0) {
			NSMutableString *submission = [NSMutableString stringWithFormat:@"u=%@&s=%@", username, md5Response];
				
			NSEnumerator *pendingEntriesEnumerator = [pendingEntries objectEnumerator];
			NSDictionary *entry;
			int index = 0;
			while (index < 10 && (entry = [pendingEntriesEnumerator nextObject])) {		// send a maximum of 10 items at once per audioscrobbler spec
				[submission appendFormat:@"&a[%d]=%@&t[%d]=%@&b[%d]=%@&m[%d]=&l[%d]=%d&i[%d]=%@",
											index, [[entry objectForKey:@"artist"] stringByURIEncoding],
											index, [[entry objectForKey:@"title"] stringByURIEncoding],
											index, [[entry objectForKey:@"album"] stringByURIEncoding],
											index, // musicbrainz id
											index, [[entry objectForKey:@"duration"] intValue],
											index, [[entry objectForKey:@"playtime"] stringByURIEncoding],
											nil];
				index++;
			}
			
			//NSPrintf(@"submitting %d of %d items:\n%@", index, [pendingEntries count], submission);
			
			NSMutableURLRequest *submissionRequest = [NSMutableURLRequest requestWithURL:submissionURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10];
			[submissionRequest setHTTPMethod:@"POST"];
			[submissionRequest setHTTPBody:[submission dataUsingEncoding:NSUTF8StringEncoding]];
			
			// send the item(s)
			NSURLConnection *submissionConnection = [[NSURLConnection alloc] initWithRequest:submissionRequest delegate:self];
			if (submissionConnection) {
				receivedData = [[NSMutableData alloc] init];
				
				NSNumber *sentMarker = [NSNumber numberWithInt:index];
				NSMutableDictionary *newRootObject = [rootObject mutableCopy];
				[newRootObject setObject:sentMarker forKey:@"sentMarker"];
				[NSKeyedArchiver archiveRootObject:newRootObject toFile:[self pathForDataFile]];
			} else {
				// couldn't make the connection
			}
			
			// items are removed in connectionDidFinishLoading:
		} else {
			// nothing to flush
		}
	}
}


/*!
    @method     addToCache
    @abstract   called after 240s or (duration / 2) of straight play
    @discussion should we validate the cache anywhere? i.e. make sure
				that we don't leave the marker in if we quit while sending?
*/
-(void)
addToCache {
	// get cache
	NSDictionary *rootObject = [NSKeyedUnarchiver unarchiveObjectWithFile:[self pathForDataFile]];
	NSMutableArray *pendingEntries = [[rootObject valueForKey:@"pendingEntries"] mutableCopy];

	if (pendingEntries == nil) {
		pendingEntries = [NSMutableArray array];								// no existing entries, bootstrap cache
	}
	
	NSDictionary *metadata = [movie metadata];
	NSArray *storageFormats = [metadata allKeys];
	if ([storageFormats count] > 0) {
		NSString *artist = nil;
		NSString *title = nil;
		NSString *album = nil;
		
		// see QTMovie (Metadata) -metadataDescription for commentary on this
		NSDictionary *qtMetaData = [metadata objectForKey:[NSString stringWithFourCharCode:kQTMetaDataStorageFormatQuickTime]];
		NSDictionary *iTunesMetaData = [metadata objectForKey:[NSString stringWithFourCharCode:kQTMetaDataStorageFormatiTunes]];
		NSDictionary *id3MetaData = [metadata objectForKey:[NSString stringWithFourCharCode:kQTMetaDataStorageFormatUserData]];
		if (qtMetaData) {
			artist = [qtMetaData objectForKey:@"com.apple.quicktime.artist"];
			title = [qtMetaData objectForKey:@"com.apple.quicktime.displayname"];
			album = [qtMetaData objectForKey:@"com.apple.quicktime.album"];
			
		} else if (iTunesMetaData) {
			artist = [iTunesMetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextArtist]];
			title = [iTunesMetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextFullName]];
			album = [iTunesMetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextAlbum]];
			
		} else if (id3MetaData) {
			artist = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextArtist]];
			title = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextFullName]];
			album = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextAlbum]];
		}
		if (!artist) {															// last ditch attempt to get an artist name
			artist = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextPerformers]];
		}
		
		if (artist && title && album) {											// only submit if we have enough info
			NSMutableDictionary *newSubmission = [NSMutableDictionary dictionary];
			[newSubmission setValue:[NSNumber numberWithInt:[movie durationInSeconds]] forKey:@"duration"];
			[newSubmission setValue:[dateFormatter stringFromDate:[NSDate date]] forKey:@"playtime"];
			[newSubmission setValue:artist forKey:@"artist"];
			[newSubmission setValue:title forKey:@"title"];
			[newSubmission setValue:album forKey:@"album"];
			
			// add new submission to existing items
			[pendingEntries addObject:newSubmission];
			
			// save out to cache
			NSMutableDictionary *newRootObject = [NSMutableDictionary dictionaryWithObject:pendingEntries forKey:@"pendingEntries"];
			[NSKeyedArchiver archiveRootObject:newRootObject toFile:[self pathForDataFile]];
			
			if (handshakeCompleted) {
				if (failureCount <= 3)											// after 3 failures, give up until next invocation
					[self flushCache];
			} else {
				[self handshake];
			}
		}
	}
}


/*!
    @method     recacheSentItems
    @abstract   items were not sent correctly for whatever reason, so add 
				them back to the pendingEntries list (i.e. delete the sent
				items marker)
    @discussion (comprehensive description)
*/
-(void)
recacheSentItems {
	NSMutableDictionary *rootObject = [[NSKeyedUnarchiver unarchiveObjectWithFile:[self pathForDataFile]] mutableCopy];
	[rootObject removeObjectForKey:@"sentMarker"];
	[NSKeyedArchiver archiveRootObject:rootObject toFile:[self pathForDataFile]];
}


-(void)
removeSentItemsFromCache {
	NSDictionary *rootObject = [NSKeyedUnarchiver unarchiveObjectWithFile:[self pathForDataFile]];
	NSMutableArray *pendingEntries = [[rootObject objectForKey:@"pendingEntries"] mutableCopy];
	
	NSRange sentRange;
	sentRange.location = 0;
	sentRange.length = [[rootObject objectForKey:@"sentMarker"] intValue];
	
	[pendingEntries removeObjectsInRange:sentRange];
	NSDictionary *newRootObject = [NSDictionary dictionaryWithObject:pendingEntries forKey:@"pendingEntries"];
	[NSKeyedArchiver archiveRootObject:newRootObject toFile:[self pathForDataFile]];
}


#pragma mark -
#pragma mark connection delegate methods

-(void)
connection:(NSURLConnection *) connection didReceiveResponse:(NSURLResponse *) response {
	[receivedData setLength:0];
}


-(void)
connection:(NSURLConnection *) connection didReceiveData:(NSData *) data {
	[receivedData appendData:data];
}


// keep track of failures
-(void)
connection:(NSURLConnection *) connection didFailWithError:(NSError *) error {
	[connection release];
	[receivedData release];
	
	failureCount++;
	
	NSPrintf(@"Connection failed! Error - %@ %@",
          [error localizedDescription],
          [[error userInfo] objectForKey:NSErrorFailingURLStringKey]);
}


/*!
    @method     connectionDidFinishLoading:
    @abstract   (brief description)
    @discussion this should have the crap safety checked out of it
*/
-(void)
connectionDidFinishLoading:(NSURLConnection *) connection {
	NSString *responseString = [[NSString alloc] initWithData:receivedData encoding:NSUTF8StringEncoding];
	//NSPrintf(@"connectionDidFinishLoading:\n%@", responseString);
	
	// UPDATE response testing
	//[responseString release];
	//responseString = @"UPDATE http://www.doequalsglory.com/qtplay/\n123456\nhttp://62.216.251.205:80/protocol_1.1\nINTERVAL 1";
	
	// FAILED response testing
	//[responseString release];
	//responseString = @"FAILED this failed because poopy\nINTERVAL 1";
	
	// BADUSER response testing
	//[responseString release];
	//responseString = @"BADUSER\nINTERVAL 1";

	NSScanner *scanner = [NSScanner scannerWithString:responseString];
	
	NSString *response;
	if ([scanner scanUpToCharactersFromSet:[scanner charactersToBeSkipped] intoString:&response]) {
		
		// handshaking responses
		if ([response isEqualToString:@"UPTODATE"] || [response isEqualToString:@"UPDATE"]) {
			if ([response isEqualToString:@"UPDATE"]) {
				NSString *updateURLString;
				[scanner scanUpToCharactersFromSet:[scanner charactersToBeSkipped] intoString:&updateURLString];
				NSPrintf(@"qtplay is out of date. get a new version at: %@", updateURLString);
			}
			
			NSString *challenge;
			// does the scanner return an autoreleased object?
			[scanner scanUpToCharactersFromSet:[scanner charactersToBeSkipped] intoString:&challenge];
			[md5Response release];
			md5Response = [[[password stringByAppendingString:challenge] md5Digest] retain];
			
			[submissionURL release];
			NSString *submissionURLString;
			[scanner scanUpToCharactersFromSet:[scanner charactersToBeSkipped] intoString:&submissionURLString];
			submissionURL = [[[NSURL alloc] initWithString:submissionURLString] retain];
			
			handshakeCompleted = YES;
			
			// we want to do this _after releasing receivedData
			[self performSelector:@selector(flushCache) withObject:nil afterDelay:0.0];
			//[self flushCache];
			
		} else if ([response isEqualToString:@"FAILED"]) {
			NSString *failureString;
			// failure string may contain whitespace, scan to newline only
			[scanner scanUpToString:@"\n" intoString:&failureString];
			
			// bastards use FAILED for both handshake and submission..
			if (handshakeCompleted) {
				NSPrintf(@"last.fm submission failed: %@", failureString);
				
				// submit failed, re-cache sent items
				[self recacheSentItems];
			} else {
				NSPrintf(@"last.fm login failed: %@", failureString);
			}
			
			failureCount++;
			
		} else if ([response isEqualToString:@"BADUSER"]) {
			NSPrintf(@"sorry, last.fm username is invalid");
			usernameInvalid = YES;												// usernameInvalid overrides failureCount
		}
		
		
		// submission responses
		else if ([response isEqualToString:@"OK"]) {
			[self removeSentItemsFromCache];
			[self flushCache];													// send more
			
		} else if ([response isEqualToString:@"BADAUTH"]) {						// re-handshake
			NSPrintf(@"last.fm: badauth");										
			[self recacheSentItems];											// submit failed, re-cache sent items
			failureCount++;
			
		} else {																// unknown response, HARD FAILURE
			failureCount++;
			
			goto exit;
		}
		
		NSString *intervalString;
		[scanner scanUpToCharactersFromSet:[scanner charactersToBeSkipped] intoString:&intervalString];
		if ([intervalString isEqualToString:@"INTERVAL"]) {
			[scanner scanInt:&interval];
		}
	}

exit:		
	[connection release];
	[receivedData release];
	receivedData = nil;
}


/*!
    @method     connection:willSendRequest:redirectResponse
    @abstract   (brief description)
    @discussion allow redirects
*/
-(NSURLRequest *)
connection:(NSURLConnection *) connection
willSendRequest:(NSURLRequest *) request
redirectResponse:(NSURLResponse *) redirectResponse {

	return request;
}

@end
