/**
 * NSString_Digest.m
 *
 * Created on 06-09-15.
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

#import "NSString_Digest.h"

#import <openssl/evp.h>
#import <openssl/err.h>


// http://lists.apple.com/archives/cocoa-dev/2006/May/msg02169.html

@implementation NSString (Digest)

-(NSString *)
md5Digest {
	NSData *data = [self dataUsingEncoding:NSUTF8StringEncoding];
	
	EVP_MD_CTX mdctx;
	unsigned char md_value[EVP_MAX_MD_SIZE];
	unsigned int md_len;
	EVP_DigestInit(&mdctx, EVP_md5());
	EVP_DigestUpdate(&mdctx, [data bytes], [data length]);
	EVP_DigestFinal(&mdctx, md_value, &md_len);
	
	NSMutableString *result = [NSMutableString string];
	
	int i;
	for (i = 0; i < md_len; i++) {
		[result appendFormat:@"%02x", md_value[i]];
	}
	
	return result;
}

@end
