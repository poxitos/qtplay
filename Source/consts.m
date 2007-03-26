/**
 * consts.m
 * qtplay
 *
 * Created on 06-09-27.
 *
 * Copyright (c) 2006, Ritchie Argue
 *
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * •   Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 * •   Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 * •   Neither the name of the <ORGANIZATION> nor the names of its contributors
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

#import "consts.h"


NSString				*const kVersionFormat		= @"qtplay v%d.%d.%d%@%@ (c) 2006 ritchie argue\nbased on Quicktime Player by Sarah Childers\nqtplay uses argtable by Stewart Heitmann, licensed under the LGPL";
const UInt8				kVersionMajor				= 1;
const UInt8				kVersionMinor				= 4;
const UInt8				kVersionRevision			= 0;
NSString				*const kVersionStatus		= @"pre9";

#if defined(LATIN1)
NSString				*const kVersionEncoding		= @"(latin1)";
#else
NSString				*const kVersionEncoding		= @"(unicode)";
#endif

char					*const kStrProgName			= "qtplay";
