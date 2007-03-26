/**
 * NSString_FourCharCode.m
 *
 * Created on 06-09-17.
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

#import "NSString_FourCharCode.h"


@implementation NSString (FourCharCode)

// why not return an (NSString *) type? I return id
// to be the same as all the rest of the string factory methods
+(id)
stringWithFourCharCode:(unsigned int) fourCharCode {
	fourCharCode = EndianU32_BtoN(fourCharCode);
	
	char c0 = *((char *) &fourCharCode + 0);
	char c1 = *((char *) &fourCharCode + 1);
	char c2 = *((char *) &fourCharCode + 2);
	char c3 = *((char *) &fourCharCode + 3);
	
	return [NSString stringWithFormat:@"%c%c%c%c", c0, c1, c2, c3];
}

-(unsigned int)
fourCharCode {
	unsigned int fourCharCode;
	
	const char *bytes = [[self dataUsingEncoding:NSUTF8StringEncoding] bytes];
	
	*((char *) &fourCharCode + 0) = *(bytes + 0);
	*((char *) &fourCharCode + 1) = *(bytes + 1);
	*((char *) &fourCharCode + 2) = *(bytes + 2);
	*((char *) &fourCharCode + 3) = *(bytes + 3);
	
	return EndianU32_NtoB(fourCharCode);
}

@end
