/**
 * qtplay.m
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

#import <Foundation/Foundation.h>

#import "DEGQTPlayer.h"
#import "DEGArgParser.h"


int
main (int argc, const char * argv[]) {
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];

	DEGArgParser *parser = [[DEGArgParser alloc] initWithArgc:argc argv:argv];
	
	NSDictionary *args = [[parser args] retain];
	NSArray *URLs = [[parser URLs] retain];
	
	[parser release];
	
	if ([args verbose]) {
		NSPrintf(@"args %@\n\n", args);
	}
	
	if ([URLs count] > 0) {
		QTPlayer *player = [[QTPlayer alloc] initWithArgs:args urls:URLs];
		[player start];
		
		if ([args verbose]) {
			NSPrintf(@"starting runloop");
		}
		
		// start the runloop to keep the player responsive to notifications etc.
		// we could poll for exits, as per
		// https://developer.apple.com/documentation/Cocoa/Conceptual/InputControl/Tasks/runningloops.html
		// 
		// or alternatively we can self-pipe again to cause the runloop to fire
		while ([player shouldKeepRunning] && [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
		
		if ([args verbose]) {
			NSPrintf(@"runloop stopped, shutting down");
		}
		
		if ([player retainCount] > 1) {
			NSPrintf(@"DEGQTPlayer overretained");
		}
		
		[player release];
	}
	
	[URLs release];
	[args release];
		
	[pool release];
	
    return 0;
}