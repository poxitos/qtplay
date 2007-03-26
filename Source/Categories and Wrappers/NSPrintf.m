/**
 * NSPrintf.m
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

#import "NSPrintf.h"


/*!
	@method     NSPrintf
	@abstract   (brief description)
	@discussion varargs version of NSPrint presented at
				http://www.sveinbjorn.org/objectivec_stdout
 */
void
NSPrintf(NSString *fmtStr, ...) {
	va_list argp;
	va_start(argp, fmtStr);
	
	NSString *str = [[NSString alloc] initWithFormat:fmtStr arguments:argp];
	
	static BOOL carriageReturn = NO;
	
	if (carriageReturn && ![str hasPrefix:@"\r"])
		[@"\n" writeToFile:@"/dev/stdout" atomically:NO];
	
#if defined(LATIN1)
	NSData *data = [str dataUsingEncoding:NSISOLatin1StringEncoding];			// for latin1 compatible terminals like GLterm
	[data writeToFile:@"/dev/stdout" atomically:NO];
#else
	NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];				// for utf8 compatible terminals like Terminal.app
	[data writeToFile:@"/dev/stdout" atomically:NO];
#endif
	
	if ([str hasPrefix:@"\r"]) {
		carriageReturn = YES;
		
	} else {
		carriageReturn = NO;
		
		if (![str hasSuffix:@"\n"])
			[@"\n" writeToFile:@"/dev/stdout" atomically:NO];
	}
	
	[str release];
	
	va_end(argp);
}