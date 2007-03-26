/**
 * QTMovie_Metadata.m
 * qtplay
 *
 * Created on 06-09-16.
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

#import "QTMovie_Metadata.h"
#import "NSString_FourCharCode.h"
#import <AppKit/AppKit.h>														// need this for NSImage


@implementation QTMovie (Metadata);

-(NSTimeInterval)
durationInSeconds {
	NSTimeInterval duration;
	QTGetTimeInterval([self duration], &duration);
	
	return duration;
}


-(NSTimeInterval)
currentTimeInSeconds {
	NSTimeInterval currentTime;
	QTGetTimeInterval([self currentTime], &currentTime);
	
	return currentTime;
}


/*!
    @method     objectForMetaData:item:propertyID:
    @abstract   (brief description)
    @discussion propertyID is type of data we're after: value, datatype,
				storage format, key, keyformat
*/
-(id)
objectForMetaData:(QTMetaDataRef) metaDataRef
item:(QTMetaDataItem) item
propertyID:(OSType) metaDataPropertyID {
	
	QTPropertyValueType propType;
	ByteCount			propValueSize;
	UInt32				propFlags;

	// get the size of the property
	OSStatus status = QTMetaDataGetItemPropertyInfo (metaDataRef,
													item,
													kPropertyClass_MetaDataItem,	// Metadata Item Property Class ID
													metaDataPropertyID,			// Metadata Item Property ID
													&propType,
													&propValueSize,
													&propFlags);
	
	// allocate memory to hold the property value
	NSMutableData *data = [NSMutableData dataWithLength:propValueSize];
	ByteCount propValueSizeUsed;
	
	// get the property itself
	status = QTMetaDataGetItemProperty(metaDataRef,
										item,
										kPropertyClass_MetaDataItem,			// Metadata Item Property Class ID
										metaDataPropertyID,						// Metadata Item Property ID
										propValueSize,
										[data mutableBytes],
										&propValueSizeUsed);
	
	// what are we supposed to do if the size used is incorrect?
	NSAssert(propValueSize == propValueSizeUsed, @"property item size incorrect");
	
    // QTMetaDataKeyFormat types will be native endian in our byte buffer, we need
    // big endian so they look correct when we create a string. 
    if (propType == 'code' || propType == 'itsk' || propType == 'itlk') {
    	OSTypePtr pType = (OSTypePtr)[data mutableBytes];
    	*pType = EndianU32_NtoB(*pType);
    }
	
	// object to return
	id object = nil;
	
	// post-process depending on item type
	switch (metaDataPropertyID) {
		case kQTMetaDataItemPropertyID_DataType:
			{																	// damn c block crap
				NSAssert([data length] == 4, @"data length != 4");
				UInt32 dataType = *((UInt32 *)[data bytes]);					
				object = [NSNumber numberWithUnsignedInt:dataType];
			}
			break;
		
		case kQTMetaDataItemPropertyID_Key:
			object = [[[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding] autorelease];
			break;
		
		case kQTMetaDataItemPropertyID_KeyFormat:
		case kQTMetaDataItemPropertyID_StorageFormat:
			// *Formats are OSType ie FourCharCodes, which probably makes them MacOSRoman
			NSAssert([data length] == 4, @"data length != 4");
			object = [[[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding] autorelease];
			break;
		
		default:
			{
				// get the data type - need to know to format data correctly
				NSNumber *dataType = [self objectForMetaData:metaDataRef item:item propertyID:kQTMetaDataItemPropertyID_DataType];
				
				// format object based on data type
				switch ([dataType unsignedIntValue]) {
					case kQTMetaDataTypeBinary:
						object = data;
						break;
					
					case kQTMetaDataTypeUTF8:
						object = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
						break;
					
					case kQTMetaDataTypeUTF16BE:
						object = [[[NSString alloc] initWithData:data encoding:NSUnicodeStringEncoding] autorelease];
						break;
						
					case kQTMetaDataTypeMacEncodedText:							// this had troubles dealing with ISO-8859-1 id3 tags.
																				// it seems that id3 is in Latin1, although qt claims
																				// mac encoded. when will it break? well, this still
																				// doesn't fix the userdata high-byte chars, so we
																				// still need to rely on qt
						object = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
						break;
					
					case 12:													// kQTMetaDataTypeGIFImage not defined yet
					case kQTMetaDataTypeJPEGImage:
					case kQTMetaDataTypePNGImage:
					case kQTMetaDataTypeBMPImage:
						object = [[[NSImage alloc] initWithData:data] autorelease];
						break;
					
					case kQTMetaDataTypeSignedIntegerBE:						/* The size of the integer is defined by the value size*/
						break;
					
					case kQTMetaDataTypeUnsignedIntegerBE:						/* The size of the integer is defined by the value size*/
						break;
					
					case kQTMetaDataTypeFloat32BE:
						break;
					
					case kQTMetaDataTypeFloat64BE:
						break;
						
					default:
						// not supported
						break;
				}
			}
			break;
	}
			
	return object;
}


-(NSDictionary *)
metadata {
	NSMutableDictionary *metadata = [NSMutableDictionary dictionary];

	QTMetaDataRef metaDataRef;
	OSErr err = QTCopyMovieMetaData([self quickTimeMovie], &metaDataRef);

	if (err == noErr) {
		
		NSArray *storageAndKeyFormats = [NSArray arrayWithObjects:
			[NSDictionary dictionaryWithObjectsAndKeys:							// quicktime
			[NSString stringWithFourCharCode:kQTMetaDataStorageFormatQuickTime], @"storageFormat",
			[NSString stringWithFourCharCode:kQTMetaDataKeyFormatQuickTime], @"keyFormat", nil],
			
			[NSDictionary dictionaryWithObjectsAndKeys:							// userdata
			[NSString stringWithFourCharCode:kQTMetaDataStorageFormatUserData], @"storageFormat",
			[NSString stringWithFourCharCode:kQTMetaDataKeyFormatUserData], @"keyFormat", nil],
			
			// can't use FormatWildcard to get both itunes formats, need to
			// extract them individually
			[NSDictionary dictionaryWithObjectsAndKeys:							// itunes long
			[NSString stringWithFourCharCode:kQTMetaDataStorageFormatiTunes], @"storageFormat",
			[NSString stringWithFourCharCode:kQTMetaDataKeyFormatiTunesLongForm], @"keyFormat", nil],
			
			[NSDictionary dictionaryWithObjectsAndKeys:							// itunes long
			[NSString stringWithFourCharCode:kQTMetaDataStorageFormatiTunes], @"storageFormat",
			[NSString stringWithFourCharCode:kQTMetaDataKeyFormatiTunesShortForm], @"keyFormat", nil],
			
			nil];
		
		NSEnumerator *storageAndKeyFormatEnumerator = [storageAndKeyFormats objectEnumerator];
		NSDictionary *storageAndKeyFormat;
		while (storageAndKeyFormat = [storageAndKeyFormatEnumerator nextObject]) {
			// get the number of items in each storage format
			unsigned int storageFormat = [[storageAndKeyFormat objectForKey:@"storageFormat"] fourCharCode];
			unsigned int keyFormat = [[storageAndKeyFormat objectForKey:@"keyFormat"] fourCharCode];
			ItemCount outCount = 0;
			err = QTMetaDataGetItemCountWithKey(metaDataRef, storageFormat, keyFormat, NULL, 0, &outCount);
			
			// if the storage format contains items
			if (outCount > 0) {
				NSMutableDictionary *qtStorage = [NSMutableDictionary dictionaryWithCapacity:outCount];
				
				// get a dictionary for each item
				QTMetaDataItem item = kQTMetaDataItemUninitialized;
				while (noErr == QTMetaDataGetNextItem(metaDataRef, storageFormat, item, keyFormat, NULL, 0, &item)) {
					NSString *key = [self objectForMetaData:metaDataRef item:item propertyID:kQTMetaDataItemPropertyID_Key];
					id value = [self objectForMetaData:metaDataRef item:item propertyID:kQTMetaDataItemPropertyID_Value];
					[qtStorage setValue:value forKey:key];
				}
				
				[metadata setValue:qtStorage forKey:[storageAndKeyFormat objectForKey:@"storageFormat"]];
			}
		}
	}
	
	return metadata;
}


/*!
    @method     metadataDescription
    @abstract   return a pretty string summarizing the metadata
    @discussion it seems that the quicktime storage format is just an alias into
				the id3 tag info. however, for some reason it's not always
				present. still prefer it for now as high-byte ISO-8859-1 id3
				info isn't being parsed correctly in the userdata storage format.
				unfortunately it doesn't give us access to as much data so
				special-case access to year and track #.
				
				since it's just an alias, will there ever be a case where
				userdata exists but qt doesn't? seems like there is, the
				vive la fete tracks don't have qt data for whatever reason. this
				is messed up.
				
				have to extract iTunes before id3, as the existence of iTunes
				data implies the existence of udta/meta
*/
-(NSString *)
metadataDescription {
	NSDictionary *metadata = [self metadata];
	
	NSString *artist = nil;
	NSString *title = nil;
	NSString *album = nil;
	NSString *year = nil;
	
	NSDictionary *qtMetaData = [metadata objectForKey:[NSString stringWithFourCharCode:kQTMetaDataStorageFormatQuickTime]];
	NSDictionary *iTunesMetaData = [metadata objectForKey:[NSString stringWithFourCharCode:kQTMetaDataStorageFormatiTunes]];
	NSDictionary *id3MetaData = [metadata objectForKey:[NSString stringWithFourCharCode:kQTMetaDataStorageFormatUserData]];
	if (qtMetaData) {
		artist = [qtMetaData objectForKey:@"com.apple.quicktime.artist"];
		title = [qtMetaData objectForKey:@"com.apple.quicktime.displayname"];
		album = [qtMetaData objectForKey:@"com.apple.quicktime.album"];
		// year is not defined in quicktime storage format, fall back to id3
		year = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextCreationDate]];
		
	} else if (iTunesMetaData) {
		artist = [iTunesMetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextArtist]];
		title = [iTunesMetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextFullName]];
		album = [iTunesMetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextAlbum]];
		year = [iTunesMetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextCreationDate]];
		
	} else if (id3MetaData) {
		artist = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextArtist]];
		title = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextFullName]];
		album = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextAlbum]];
		year = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextCreationDate]];
	}
	if (!artist) {																// last ditch attempt to get an artist name
		artist = [id3MetaData objectForKey:[NSString stringWithFourCharCode:kUserDataTextPerformers]];
	}
	
	if (artist && title && album) {
		if (year) {
			return [NSString stringWithFormat:@"%@ - %@ (%@): %@", artist, album, year, title];
		} else {
			return [NSString stringWithFormat:@"%@ - %@: %@", artist, album, title];
		}
	} else {
		return nil;
	}
}


-(NSString *)
loadStateDescription {
	NSString *loadStateDescription;
	
	switch ([[self attributeForKey:QTMovieLoadStateAttribute] longValue]) {
		case kMovieLoadStateLoading:
			loadStateDescription = @"loading";
			break;
			
		case kMovieLoadStateLoaded:
			loadStateDescription = @"loaded";
			break;
			
		case kMovieLoadStatePlayable:
			loadStateDescription = @"playable";
			break;
			
		case kMovieLoadStatePlaythroughOK:
			loadStateDescription = @"playthrough ok";
			break;
			
		case kMovieLoadStateComplete:
			loadStateDescription = @"complete";
			break;
		
		case kMovieLoadStateError:
		default:
			loadStateDescription = @"error";
			break;
	}
	
	return loadStateDescription;
}

@end
