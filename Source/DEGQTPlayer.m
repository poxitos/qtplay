/**
 * qtplayer.m
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

#import "DEGQTPlayer.h"

#import "NSPrintf.h"
#import "QTMovie_Metadata.h"
#import "NSString_FourCharCode.h"
#import "DEGArgParser.h"														// for NSDictionary category


@interface QTPlayer (ForwardDecls)
-(void) installSignalHandler;
-(void) removeSignalHandler;
-(void) installStdinHandler;
-(void) removeStdinHandler;

-(void) getTerminalSize;
-(void) loadTrack;
-(void) playTrack;
-(void) stop;
-(void) disableVideoTracks:(QTMovie *) aMovie;
@end

@implementation QTPlayer

-(id)
initWithArgs:(NSDictionary *) theArgs urls:(NSArray *) theURLs {
	
	self = [super init];
	if (self != nil) {
		// check for qtkit? this is untested
		NSBundle *qtKitBundle = [NSBundle bundleWithIdentifier:@"com.apple.QTKit"];
		if (qtKitBundle == nil) {
			[self release];
			return nil;
		}
		
		args = [theArgs mutableCopy];											// mutable to adjust volume etc.
		URLs = [theURLs mutableCopy];											// mutable for shuffle
		
		[self installSignalHandler];
		[self installStdinHandler];
		
		[self getTerminalSize];
		
		paused = NO;
		shouldKeepRunning = YES;
		
		// set up the scrobbler
		audioScrobbler = [[DEGAudioScrobbler alloc] initWithName:[args valueForKey:@"name"]
														password:[args valueForKey:@"password"]];
		
		exitPipe = [[NSPipe alloc] init];										// self-pipe for shutdown
		NSFileHandle *exitReadHandle = [exitPipe fileHandleForReading];
		exitWriteFileDescriptor = [[exitPipe fileHandleForWriting] fileDescriptor];
		
		[exitReadHandle readInBackgroundAndNotify];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(exit:)
													 name:NSFileHandleReadCompletionNotification
												   object:exitReadHandle];
		
		srandom([[NSDate date] timeIntervalSince1970]);							// initialize for shuffle/random play
	}
	return self;
}


-(void)
dealloc {
	[exitPipe release];

	[audioScrobbler release];

	[self removeStdinHandler];
	[self removeSignalHandler];
	
	[URLs release];
	[args release];																// do this last thing, in case [args verbose] is used somewhere..
	
	[super dealloc];
}


#pragma mark -
#pragma mark transport api

-(BOOL) shouldKeepRunning { return shouldKeepRunning; }


-(void)
start {
	displayTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
													target:self
												  selector:@selector(displayTrackInfo)
												  userInfo:nil
												   repeats:YES];
	currentIndex = 0;
	[self loadTrack];
}


#pragma mark -
#pragma mark transport


-(void)
getTerminalSize {
	struct winsize ws;
	
	if ((ioctl(fileno(stdout), TIOCGWINSZ, &ws) == -1 &&
		 ioctl(fileno(stderr), TIOCGWINSZ, &ws) == -1 &&
		 ioctl(fileno(stdin),  TIOCGWINSZ, &ws) == -1) ||
		ws.ws_col == 0) {
		//height = 25;
		terminalWidth = 80;
	} else {
		//height = ws.ws_row;
		terminalWidth = ws.ws_col;
	}
}


/*!
    @method     displayTrackInfo
    @abstract   print out track name and time
    @discussion would probably be nice to center truncate the name, but I can't
				be bothered to write up the algo to do so. if you run an 80col
				terminal, feel free to fix it.
*/
-(void)
displayTrackInfo {
	if (![args quiet] && movie != nil) {
		NSString *description = [movie metadataDescription];
		if (!description)
			description = [movie attributeForKey:QTMovieFileNameAttribute];
		
		int currentTime = [movie currentTimeInSeconds];
		if (displayCountsDown)
			currentTime = [movie durationInSeconds] - currentTime;
		
		int seconds = currentTime % 60;
		int minutes = (currentTime / 60) % 60;
		int hours = currentTime / 3600;
		
		NSString *displayTime;
		if (hours) {
			if (paused)
				displayTime = @" paused ";
			else
				displayTime = [NSString stringWithFormat:@"%02d:%02d:%02d", hours, minutes, seconds];
		} else {
			if (paused)
				displayTime = @"pause";
			else
				displayTime = [NSString stringWithFormat:@"%02d:%02d", minutes, seconds];
		}
		
		if (displayCountsDown)
			displayTime = [NSString stringWithFormat:@"(%@) ", displayTime];	// leave a space for block cursors
		else
			displayTime = [NSString stringWithFormat:@"[%@] ", displayTime];	// leave a space for block cursors
		
		if (windowResized) {
			[self getTerminalSize];
			windowResized = NO;
		}
		
		if ((terminalWidth - [displayTime length] - 4) < [description length]) {
			displayTime = [NSString stringWithFormat:@"... %@", displayTime];
		} else {
			displayTime = [NSString stringWithFormat:@"    %@", displayTime];
		}
		description = [description stringByPaddingToLength:terminalWidth - [displayTime length]
												withString:@" "
										   startingAtIndex:0];
		
		NSPrintf(@"\r%@%@", description, displayTime);							
	}
}


-(void)
loadTrack {
	NSURL *mediaURL = [URLs objectAtIndex:currentIndex];
	if ([QTMovie canInitWithURL:mediaURL]) {									// I think this may leak a little
		NSError *error;
		
		movie = [[QTMovie alloc] initWithURL:mediaURL error:&error];
		[self disableVideoTracks:movie];
		[movie setVolume:[args volume]];
		
		if ([args verbose]) {
			NSPrintf(@"initial load state: %@", [movie loadStateDescription]);
		}
		
		loadState = [[movie attributeForKey:QTMovieLoadStateAttribute] longValue];
		
		if (loadState >= kMovieLoadStateComplete) {
			[[NSNotificationCenter defaultCenter] addObserver:self
													 selector:@selector(movieDidEnd:)
														 name:QTMovieDidEndNotification
													   object:movie];
		} else {
			[[NSNotificationCenter defaultCenter] addObserver:self				// not complete yet, set up load state notifier
													 selector:@selector(loadStateDidChange:)
														 name:QTMovieLoadStateDidChangeNotification
													   object:movie];
		}
		
		if (loadState >= kMovieLoadStatePlayable) {
			if ([args verbose]) {
				NSPrintf(@"file metadata: %@", [movie metadata]);
			}
			
			[self playTrack];
			loadState = kMovieLoadStatePlaythroughOK;							// collapse Playable and PlaythroughOK into one state
		}
		
	} else {
		NSPrintf(@"couldn't load %@", mediaURL);

		[self performSelector:@selector(nextTrack)								// couldn't play this file, so we will never receive a movieDidEnd:
				   withObject:nil												// to trigger a new file. manually trigger it here
				   afterDelay:0];
	}
}


-(void)
unloadTrack {
	[movie stop];																// may have got here via ctrl-c instead of movieDidEnd
	
	[audioScrobbler releaseMovie];												// tell the scrobbler when to release the movie, instead of letting
																				// it try to sort it out on its own
	[movie release];
	
	NSPrintf(@"\r\n");
}


-(void)
playTrack {
	[movie play];
	[audioScrobbler submit:movie];
	
	[self displayTrackInfo];													// provide immediate feedback
}


-(void)
shuffle {
	if ([args shuffle]) {														// swap array[i] with array[random()];
		int newIndex = currentIndex + (random() % ([URLs count] - currentIndex));
		
		NSURL *tempURL = [URLs objectAtIndex:currentIndex];
		NSURL *newURL = [URLs objectAtIndex:newIndex];
		
		[URLs replaceObjectAtIndex:currentIndex withObject:newURL];
		[URLs replaceObjectAtIndex:newIndex withObject:tempURL];
	}
}


-(void)
nextTrack {
	[self unloadTrack];															// unload the current track - notify scrobbler
	
	if ([args loop]) {
		currentIndex = (currentIndex + 1) % [URLs count];
	} else {
		currentIndex++;
	}
	
	if (currentIndex >= [URLs count]) {
		[self stop];
		
	} else {
		[self shuffle];
		
		[self loadTrack];														// load (& play) a new track
		
		if ([args onlyone])
			currentIndex = [URLs count];										// stop after this play
	}
}


/*!
    @method     previousTrack
    @abstract   load and play the previous track
    @discussion clip or loop as appropriate
*/
-(void)
previousTrack {
	[self unloadTrack];
	
	if ([args loop]) {
		currentIndex = ((currentIndex - 1) + [URLs count]) % [URLs count];		// what the hell, c can't modulo a negative number?
	} else {
		currentIndex = MAX(0, currentIndex - 1);
	}
	
	[self loadTrack];
}


/*!
    @method     rewind
    @abstract   rewind to the previous track
    @discussion only rewind if the movie currentTime is near 0. near depends
				on dblTime in case someone has a gigantic dblTime configured
*/
-(void)
rewind {
	if (rewind && [movie currentTimeInSeconds] < 2 * [args dblTime]) {
		[self previousTrack];
	}
	rewind = YES;
	[NSObject cancelPreviousPerformRequestsWithTarget:self						// cancel existing request if it didn't fire, otherwise it over-retains
											 selector:@selector(resetRewind)
											   object:nil];
	
	[self performSelector:@selector(resetRewind)
			   withObject:nil
			   afterDelay:[args dblTime]];
}


-(void)
resetRewind {
	rewind = NO;
}


-(void)
ffwd {
	if (([movie durationInSeconds] - [movie currentTimeInSeconds]) < 2 * [args dblTime]) {
		[self nextTrack];
	}
}


/*!
    @method     seekTrackAbsolute:
    @abstract   seek by an absolute number of seconds
    @discussion seeking past the end of a track multiple times (i.e. hold down
				right arrow) eventually caused a bus error. fix this by setting
				a maximum position of duration - 0.1, and adding a -ffwd method
				to prevent 0.1s stuttering due to rewinding to duration - 0.1
*/
-(void)
seekTrackAbsolute:(NSTimeInterval) amount {
	if ([args verbose]) {
		NSPrintf(@"seekTrackAbsolute: %f", amount);
	}
	
	NSTimeInterval currentTime;
	QTGetTimeInterval([movie currentTime], &currentTime);
	
	NSTimeInterval duration;
	QTGetTimeInterval([movie duration], &duration);
	
	NSTimeInterval newTime = currentTime + amount;								
	newTime = MAX(0.0, newTime);
	newTime = MIN(duration - [args dblTime], newTime);							// if we seek past the end, it may cause a bus error

	QTTime newQTTime = QTMakeTimeWithTimeInterval(newTime);
	[movie setCurrentTime:newQTTime];

	if (amount < 0) {
		[self rewind];
	} else if (amount > 0) {
		[self ffwd];
	}
	
	[self displayTrackInfo];													// provide immediate feedback
}


/*!
    @method     seekTrackRelative:
    @abstract   seek by a percentage of the track duration
    @discussion amount in range -1..1
*/
-(void)
seekTrackRelative:(NSTimeInterval) amount {
	if ([args verbose]) {
		NSPrintf(@"seekTrackRelative: %f", amount);
	}
	
	NSTimeInterval currentTime;
	QTGetTimeInterval([movie currentTime], &currentTime);
	
	NSTimeInterval duration;
	QTGetTimeInterval([movie duration], &duration);
	
	NSTimeInterval newTime = currentTime + (duration * amount);
	newTime = MAX(0.0, newTime);
	newTime = MIN(duration - [args dblTime], newTime);							// if we seek past the end, it may cause a bus error
	
	QTTime newQTTime = QTMakeTimeWithTimeInterval(newTime);
	[movie setCurrentTime:newQTTime];
	
	if (amount < 0) {
		[self rewind];
	} else if (amount > 0) {
		[self ffwd];
	}
	
	[self displayTrackInfo];													// provide immediate feedback
}

-(void)
pauseTrack {

}

-(void)
resumeTrack {

}


/*!
    @method     stop
    @abstract   single exit point
    @discussion this must be the only exit point, else the displayTimer
				doesn't get cleaned up, and it holds a retain on the player
*/
-(void)
stop {
	NSPrintf(@"\r\n");
	[displayTimer invalidate];													// note that we didn't retain displayTimer, so just stop it, don't release
	shouldKeepRunning = NO;
	write(exitWriteFileDescriptor, &shouldKeepRunning, sizeof(BOOL));			// cause our runloop to read data so it can test the exit flag
}


#pragma mark -
#pragma mark transport notifications


/*!
    @method     loadStateDidChange
    @abstract   notification
    @discussion the load state may skip states, or notify changes to the same
				state. handy. collapse Playable and PlaythroughOK.
*/
-(void)
loadStateDidChange:(NSNotification *) aNotification {
	UInt32 newLoadState = [[movie attributeForKey:QTMovieLoadStateAttribute] longValue];
	
	if (newLoadState <= loadState) {
		return;
	}
	
	if ([args verbose]) {
		NSPrintf(@"loadStateDidChange: %@", [movie loadStateDescription]);
	}
	
	if (newLoadState >= kMovieLoadStateComplete) {
		[[NSNotificationCenter defaultCenter] removeObserver:self
														name:QTMovieLoadStateDidChangeNotification
													  object:movie];
		
		[[NSNotificationCenter defaultCenter] addObserver:self
										 selector:@selector(movieDidEnd:)
											 name:QTMovieDidEndNotification
										   object:movie];
		
		loadState = newLoadState;
	
	} else if (newLoadState >= kMovieLoadStatePlayable) {
		[self playTrack];
		loadState = kMovieLoadStatePlaythroughOK;								// collapse Playable and PlaythroughOK into one state
	
	} else {
		loadState = newLoadState;
	}
}


-(void)
movieDidEnd:(NSNotification *) aNotification {
	if ([args verbose]) {
		NSPrintf(@"movieDidEnd");
	}
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:QTMovieDidEndNotification object:movie];
	
	[self nextTrack];
}


#pragma mark -
#pragma mark misc
/*!
    @method     disableVideoTracks
    @abstract   can cut cpu usage significantly when playing movie files
    @discussion don't worry about cutting tracks to prevent video windows
				showing up, doesn't appear to happen with QTKit
				
				something in here caused a seg fault on shutdown with movies
				containing BaseMediaType tracks. fixed by using a smaller auto-
				release pool here. why does this work? who knows.. related info:
				http://lists.apple.com/archives/quicktime-api/2005/Jun/msg00185.html
*/
-(void)
disableVideoTracks:(QTMovie *) aMovie {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	NSArray *tracks = [aMovie tracks];
	NSEnumerator *trackEnumerator = [tracks objectEnumerator];
	QTTrack *track;
	while (track = [trackEnumerator nextObject]) {
		//what about mpegs with interleaved data? they are type @"MPEG"
		NSString *mediaTypeString = [track attributeForKey:QTTrackMediaTypeAttribute];
		
		if ([mediaTypeString fourCharCode] == VideoMediaType) {
			[track setEnabled:NO];
		}
		
		// playlists are of type @"text"
	}
	[pool release];
}


/*!
    @method     exit:
    @abstract   (brief description)
    @discussion dummy notification handler to get input on the runloop
				(and therefore to allow the exit condition to be tested)
*/
-(void)
exit:(NSNotification *) notification {
	NSFileHandle *exitHandle = [notification object];
	
	// reschedule exit fileHandle just in case a notification
	// was sent erroneously
	[exitHandle readInBackgroundAndNotify];
}


#pragma mark -
#pragma mark stdin handling

/*!
	@method     disableLineBuffering
	@abstract   http://www.gmonline.demon.co.uk/cscene/CS6/CS6-02.html
	@discussion linebuffering appears to get turned on again during a suspend/
				continue cycle, so disable again when continuing
 */
-(void)
disableLineBuffering {
	struct termios changes;
	tcgetattr(fileno(stdin), &originalTermioSettings);
	changes = originalTermioSettings;
	changes.c_lflag &= ~(ICANON|ECHO);
	tcsetattr(fileno(stdin), TCSADRAIN, &changes);
}


-(void)
enableLineBuffering {
	tcsetattr(fileno(stdin), TCSADRAIN, &originalTermioSettings);
}


/*!
    @method     installStdinHandler
    @abstract   listen for key presses on stdin, notify player
    @discussion this appears to stop working after suspend/resume
*/
-(void)
installStdinHandler {
	[self disableLineBuffering];

	stdinHandle = [[NSFileHandle fileHandleWithStandardInput] retain];
	[stdinHandle readInBackgroundAndNotify];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(handleInput:)
												 name:NSFileHandleReadCompletionNotification
											   object:stdinHandle];
}


-(void)
removeStdinHandler {
	[[NSNotificationCenter defaultCenter] removeObserver:self
													name:NSFileHandleReadCompletionNotification
												  object:stdinHandle];
	[stdinHandle release];
	
	[self enableLineBuffering];
}


/*!
    @method     handleInput:
    @abstract   read keys from stdin
    @discussion consider depending less on home/end pgup/pgdown for laptop users?
*/
-(void)
handleInput:(NSNotification *) notification {
	NSFileHandle *handle = [notification object];
	NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];

	NSString *stringData = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
	
	// this dispatch is a bit gross, is there a cleaner way?
	if ([stringData isEqualToString:@"q"]) {									// 'q': quit
		[self stop];
	
	} else if ([stringData isEqualToString:@"/"]) {								// '/': toggle display direction
		displayCountsDown = !displayCountsDown;
		[self displayTrackInfo];												// provide immediate feedback
	
	} else if ([stringData isEqualToString:@"0"]) {								// '0': toggle mute
		[movie setMuted:![movie muted]];
	
	} else if ([stringData isEqualToString:@"-"]) {								// '-': decrease volume 10%
		float vol = MAX(0.0, [args volume] - 0.1);
		[movie setVolume:vol];
		[args setVolume:vol];

	} else if ([stringData isEqualToString:@"+"] || [stringData isEqualToString:@"="]) {	// '+': increase volume 10%
		float vol = MIN(1.0, [args volume] + 0.1);
		[movie setVolume:vol];
		[args setVolume:vol];
	
	} else if ([stringData isEqualToString:@" "]) {								// ' ': toggle pause
		if (paused) {
			[movie play];
		} else {
			[movie stop];
		}
		paused = !paused;
		[self displayTrackInfo];												// provide immediate feedback
		
	} else if ([stringData isEqualToString:@"\e"]) {							// escape: quit
		[self stop];
		
	} else if ([stringData isEqualToString:@"\e\133\101"]) {					// up arrow: skip backward 10%
		[self seekTrackRelative:-0.1];
		
	} else if ([stringData isEqualToString:@"\e\133\102"]) {					// down arrow: skip forward 10%
		[self seekTrackRelative:0.1];

	} else if ([stringData isEqualToString:@"\e\133\104"]) {					// left arrow: skip backward 10s
		[self seekTrackAbsolute:-10];

	} else if ([stringData isEqualToString:@"\e\133\103"]) {					// right arrow: skip forward 10s
		[self seekTrackAbsolute:10];
	
	} else if ([stringData isEqualToString:@"\e\133\065\176"]) {				// page up: skip backward 60s
		[self seekTrackAbsolute:-60];
		
	} else if ([stringData isEqualToString:@"\e\133\066\176"]) {				// page down: skip forward 60s
		[self seekTrackAbsolute:60];

	} else if ([stringData isEqualToString:@"\e\133\061\176"]) {				// home: track start
		[movie gotoBeginning];
		[self rewind];
		
	} else if ([stringData isEqualToString:@"\e\133\064\176"] ||				// end or '.': track end
			   [stringData isEqualToString:@"."]) {								
		[self seekTrackAbsolute:0];												// cheap hack to notify scrobbler of seek
		[self nextTrack];
			
	} else {
		if ([args verbose]) 
			NSPrintf(@"stdin received %@: %@", data, stringData);
	}
		
	[stringData release];
	
	// reschedule stdin fileHandle
	[handle readInBackgroundAndNotify];
}


#pragma mark -
#pragma mark signal handling

int sigPipeWrite;																// this needs to be a global so the c-based handler can use it

/*!
    @method     sigHandler()
    @abstract   (brief description)
    @discussion handle signals via the self-pipe trick. just pass signo up to
				-handleSignal:
				http://cr.yp.to/docs/selfpipe.html
*/
void
sigHandler(int signo) {
	write(sigPipeWrite, &signo, sizeof(int));
}


-(void)
installSignalHandler {
	sigPipe = [[NSPipe alloc] init];
	
	sigPipeWrite = [[sigPipe fileHandleForWriting] fileDescriptor];				// store pipe write file descriptor to a global so our c-based handler can use it
	
	sigReadHandle = [sigPipe fileHandleForReading];
	[sigReadHandle readInBackgroundAndNotify];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleSignal:) name:NSFileHandleReadCompletionNotification object:sigReadHandle];
	
	signal(SIGINT, &sigHandler);												// now that the pipe is set up, it's safe to install signal handlers
	signal(SIGTSTP, &sigHandler);
	signal(SIGCONT, &sigHandler);
	signal(SIGWINCH, &sigHandler);
}


-(void)
removeSignalHandler {
	signal(SIGINT, SIG_DFL);
	signal(SIGTSTP, SIG_DFL);
	signal(SIGCONT, SIG_DFL);
	signal(SIGWINCH, SIG_DFL);
	
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:sigReadHandle];
	[sigPipe release];
}

/*!
    @method     handleSignal:
    @abstract   (brief description)
    @discussion my goodness this is so much nicer than the global flags the old
				version was using to handle signals.
*/
-(void)
handleSignal:(NSNotification *) notification {
	NSFileHandle *sigHandle = [notification object];
	NSData *data = [[notification userInfo] objectForKey:NSFileHandleNotificationDataItem];

	int signal;
	[data getBytes:&signal length:sizeof(int)];
	
	switch (signal) {
		case SIGINT:
			if ([args verbose]) {
				NSPrintf(@"interrupt signal caught");
			}
				
			if (caughtSIGINT) {													// if 2nd SIGINT comes in before the timer resets our flag, we exit
				[NSObject cancelPreviousPerformRequestsWithTarget:self
														 selector:@selector(resetSIGINT)
														   object:nil];
				[self stop];
				
			} else {
				caughtSIGINT = YES;
				[self performSelector:@selector(resetSIGINT)					// this retains, make sure to cancel it to release if it doesn't fire
						   withObject:nil
						   afterDelay:[args dblTime]];
				
				[self seekTrackAbsolute:0];										// cheap hack to notify scrobbler of seek
				[self nextTrack];
			}
			break;
		
		case SIGTSTP:
			if ([args verbose]) {
				NSPrintf(@"tty stop signal caught");
			}
			
			[movie stop];
			[self enableLineBuffering];
			
			kill(getpid(), SIGSTOP);
			
			break;
			
		case SIGCONT:
			if ([args verbose]) {
				NSPrintf(@"continue signal caught");
			}
			
			// linebuffering appears to get turned on again during a suspend/
			// continue cycle, so disable again when continuing
			[self disableLineBuffering];
			
			// stop/continue w/o a [movie stop/play] may cause a buffering gap
			// on resume
			[movie play];
			break;
		
		case SIGWINCH:															// Terminal.crapp only updates on mouseup after resizing is finished
			if ([args verbose]) {
				NSPrintf(@"window changed signal caught", terminalWidth);
			}
			
			windowResized = TRUE;
			
			break;
			
		default:
			if ([args verbose]) {
				NSPrintf(@"signal %d caught", signal);
			}
	}
	
	// reschedule signal fileHandle
	[sigHandle readInBackgroundAndNotify];
}


/*!
    @method     resetSIGINT:
    @abstract   (brief description)
    @discussion reset SIGINT flag timer callback
*/
-(void)
resetSIGINT {
	caughtSIGINT = NO;
}

@end