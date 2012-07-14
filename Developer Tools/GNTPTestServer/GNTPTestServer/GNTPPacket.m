//
//  GNTPPacket.m
//  GNTPTestServer
//
//  Created by Daniel Siemer on 7/2/12.
//  Copyright (c) 2012 The Growl Project, LLC. All rights reserved.
//

#import "GNTPPacket.h"
#import "GNTPKey.h"
#import "GCDAsyncSocket.h"
#import "NSStringAdditions.h"
#import "GNTPUtilities.h"
#import "GrowlDefines.h"
#import "GrowlDefinesInternal.h"
#import "GCDAsyncSocket.h"
#import <CommonCrypto/CommonHMAC.h>

#if GROWLHELPERAPP
#import "GNTPSubscriptionController.h"
#endif

@interface GNTPPacket ()

@property (nonatomic, retain) NSString *incomingDataIdentifier;
@property (nonatomic, assign) NSUInteger incomingDataLength;
@property (nonatomic, assign) BOOL incomingDataHeaderRead;

@end

@implementation GNTPPacket

@synthesize key = _key;
@synthesize connectedHost = _connectedHost;
@synthesize guid = _guid;
@synthesize action = _action;
@synthesize growlDict = _growlDict;
@synthesize gntpDictionary = _gntpDictionary;
@synthesize dataBlockIdentifiers = _dataBlockIdentifiers;
@synthesize state = _state;
@synthesize keepAlive = _keepAlive;

@synthesize incomingDataIdentifier = _incomingDataIdentifier;
@synthesize incomingDataLength = _incomingDataLength;
@synthesize incomingDataHeaderRead = _incomingDataHeaderRead;

#pragma mark Validation Methods
+(BOOL)isValidKey:(GNTPKey*)key
		forPassword:(NSString*)password
{
   GNTPKey *remoteKey = [[[GNTPKey alloc] initWithPassword:password
															hashAlgorithm:[key hashAlgorithm]
													encryptionAlgorithm:[key encryptionAlgorithm]] autorelease];
   [remoteKey setSalt:[key salt]];
   NSData *IV = [key IV];
   [remoteKey generateKey];
   if(IV)
      [remoteKey setIV:IV];
   
   if ([HexEncode([key keyHash]) caseInsensitiveCompare:HexEncode([remoteKey keyHash])] == NSOrderedSame)
      return YES;
   return NO;
}
+ (BOOL)isAuthorizedPacketType:(NSString*)action
							  withKey:(GNTPKey*)key
							originKey:(GNTPKey*)originKey
							forSocket:(GCDAsyncSocket*)socket
							errorCode:(GrowlGNTPErrorCode*)errCode
						 description:(NSString**)errDescription
{
   NSString *conHost = nil;
   if([socket connectedHost])
      conHost = [socket connectedHost];
   else{
      NSLog(@"We dont know what host sent this (will show as missing hash string error)");
      *errCode = GrowlGNTPInternalServerErrorErrorCode;
      *errDescription = NSLocalizedString(@"We encountered an error parsing the packet, we don't know where it came from", @"GNTP error");
      return NO;
   }
#if GROWLHELPERAPP
   GrowlPreferencesController *preferences = [GrowlPreferencesController sharedController];
   if(![conHost isLocalHost])
   {
      /* These two cases are for if the socket has to be open for subscription, but not remote notes/registration, or vice versa */
      if(![preferences isGrowlServerEnabled] && ([action caseInsensitiveCompare:GrowlGNTPNotificationMessageType] == NSOrderedSame ||
																 [action caseInsensitiveCompare:GrowlGNTPRegisterMessageType] == NSOrderedSame))
      {
         *errCode = GrowlGNTPUnauthorizedErrorCode;
         *errDescription = NSLocalizedString(@"Incoming remote notifications and registrations have been disabled by the user", @"GNTP unauthorized packet error message");
         return NO;
      }
      
      if(![preferences isSubscriptionAllowed] && [action caseInsensitiveCompare:GrowlGNTPSubscribeMessageType] == NSOrderedSame) {
         *errCode = GrowlGNTPUnauthorizedErrorCode;
         *errDescription = NSLocalizedString(@"Incoming subscription requests have been disabled by the user", @"GNTP unathorized packet error message");
         return NO;
      }
   }
#endif
   
   //There are a number of cases in which a password isn't required, some are optional
   BOOL passwordRequired = YES;
	BOOL isResponseType = ([action caseInsensitiveCompare:GrowlGNTPErrorResponseType] == NSOrderedSame || 
								  [action caseInsensitiveCompare:GrowlGNTPOKResponseType] == NSOrderedSame ||
								  [action caseInsensitiveCompare:GrowlGNTPCallbackTypeHeader] == NSOrderedSame);
   
   if([conHost isLocalHost] && [key hashAlgorithm] == GNTPNoHash && [key encryptionAlgorithm] == GNTPNone)
      return YES;
   
   //This is mainly for future reference, responses are supposed to have security by spec, but it isn't implemented in GfW or Growl.app
#if GROWLHELPERAPP
   if(![preferences boolForKey:@"RequireSecureGNTPResponses"] && isResponseType){
      passwordRequired = NO;
   }
#endif
   
   //New setting to allow no encryption when password is empty
   NSString *remotePassword = @"TESTING";
#if GROWLHELPERAPP
	remotePassword = [preferences remotePassword];
   if(![preferences boolForKey:@"RequireGNTPSecurityWhenPasswordEmpty"]) {
      if(!remotePassword || [remotePassword isEqualToString:@""])
         passwordRequired = NO;
   }
#endif
   
   //Despite all the above, if we have an encryption algorithm, we require a password setup to decrypt
   if([key encryptionAlgorithm] != GNTPNone)
      passwordRequired = YES;
   
   //If we dont have a hash algorithm, and we require password, we dont have what we need
   if([key hashAlgorithm] == GNTPNoHash && passwordRequired)
      return NO;
   
   //We dont need a password, we dont have a hash algorithm, and we dont have encryption
   if(!passwordRequired && [key hashAlgorithm] == GNTPNoHash)
      return YES;
   
   //At this point, we know we need a password, for decryption, or just authorization
	if(isResponseType){
		//check hash against the origin packet, regardless of subscription or not, this should be valid
		if (originKey && [HexEncode([originKey keyHash]) caseInsensitiveCompare:HexEncode([key keyHash])] == NSOrderedSame)
			return YES;
	}else{
		//Try our remote password
		if([GNTPPacket isValidKey:key
						  forPassword:remotePassword])
			return YES;
		
		//If we've gotten here, we are going to assume its a subscription passworded REGISTER or SUBSCRIBE
		NSString *subscriptionPassword = @"SUBSCRIPTION";
#if GROWLHELPERAPP
		subscriptionPassword = [[GNTPSubscriptionController sharedController] passwordForLocalSubscriber:conHost];
#endif
		if(subscriptionPassword &&
			![subscriptionPassword isEqualToString:@""] &&
			[GNTPPacket isValidKey:key
						  forPassword:subscriptionPassword]) 
		{
			return YES;
		}
	}
   
   return NO;
}
+(GNTPKey*)keyForSecurityHeaders:(NSArray*)headers 
							  errorCode:(GrowlGNTPErrorCode*)errCode
							description:(NSString**)errDescription
{
	GNTPKey *key = [[[GNTPKey alloc] init] autorelease];
	
	NSArray *encryptionSubstrings = [[headers objectAtIndex:2] componentsSeparatedByString:@":"];
	NSString *packetEncryptionAlgorithm = [[encryptionSubstrings objectAtIndex:0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	GrowlGNTPEncryptionAlgorithm algorithm = [GNTPKey encryptionAlgorithmFromString:packetEncryptionAlgorithm];
	[key setEncryptionAlgorithm:algorithm]; //this should be None if there is only one item
	if([GNTPKey isSupportedEncryptionAlgorithm:packetEncryptionAlgorithm])
	{
		if([encryptionSubstrings count] == 2)
			[key setIV:HexUnencode([encryptionSubstrings objectAtIndex:1])];
		else {
			if ([key encryptionAlgorithm] != GNTPNone) {
				*errCode = GrowlGNTPUnauthorizedErrorCode;
				*errDescription = NSLocalizedString(@"Missing initialization vector for encryption", /*comment*/ @"GNTP packet parsing error");
				key = nil;
			}
		}
	}else{
		*errCode = GrowlGNTPUnauthorizedErrorCode;
		*errDescription = [NSString stringWithFormat:NSLocalizedString(@"Unsupported encryption type, %@", @"GNTP packet with an unsupported encryption algorithm"), packetEncryptionAlgorithm];
		key = nil;
	}
	
	if(!errDescription && errCode == 0 && key != nil)
	{
		BOOL hashStringError = NO;
		if([headers count] == 4)
		{
			NSString *item4 = [[headers objectAtIndex:3] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			if([item4 caseInsensitiveCompare:@""] == NSOrderedSame){
				NSLog(@"Empty item 4, possibly a flaw in the GNTP sender, ignoring");
			} else {
				NSArray *keySubstrings = [item4 componentsSeparatedByString:@":"];
				NSString *keyHashAlgorithm = [keySubstrings objectAtIndex:0];
				if([GNTPKey isSupportedHashAlgorithm:keyHashAlgorithm]) {
					[key setHashAlgorithm:[GNTPKey hashingAlgorithmFromString:keyHashAlgorithm]];
					if([keySubstrings count] == 2) {
						NSArray *keyHashStrings = [[keySubstrings objectAtIndex:1] componentsSeparatedByString:@"."];
						if([keyHashStrings count] == 2) {
							[key setKeyHash:HexUnencode([keyHashStrings objectAtIndex:0])];
							[key setSalt:HexUnencode([[keyHashStrings objectAtIndex:1] substringWithRange:NSMakeRange(0, [[keyHashStrings objectAtIndex:1] length])])];
							//we will do actual check of all this in isAuthorizedPacket
						}
						else 
							hashStringError = YES;
					}
					else
						hashStringError = YES;
				}
				else
					hashStringError = YES;
			}
		}
		
		
		if(hashStringError)
		{
			if(!errDescription && errCode == 0)
			{
				NSLog(@"There was a missing <hashalgorithm>:<keyHash>.<keySalt> with encryption or remote, set error and return appropriately");
				*errCode = GrowlGNTPUnauthorizedErrorCode;
				*errDescription = NSLocalizedString(@"Missing, malformed, or invalid key hash string", @"GNTP packet parsing error");
				key = nil;
			}
		}
	}
	return key;
}

#pragma mark Header Parsing methods
+(NSString*)headerKeyFromHeader:(NSString*)header {
	NSInteger location = [header rangeOfString:@": "].location;
	if(location != NSNotFound)
		return [header substringToIndex:location];
	return nil;
}
+(NSString*)headerValueFromHeader:(NSString*)header{
	NSInteger location = [header rangeOfString:@": "].location;
	if(location != NSNotFound)
		return [header substringFromIndex:location + 2];
	return nil;
}
+(void)enumerateHeaders:(NSString*)headersString 
				  withBlock:(GNTPHeaderBlock)headerBlock 
{
	NSArray *headers = [headersString componentsSeparatedByString:@"\r\n"];
	[headers enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if(!obj || [obj isEqualToString:@""] || [obj isEqualToString:@"\r\n"])
			return;
		
		NSString *headerKey = [GNTPPacket headerKeyFromHeader:obj];
		NSString *headerValue = [GNTPPacket headerValueFromHeader:obj];
		if(headerKey && headerValue){
			if(headerBlock(headerKey, headerValue))
				*stop = YES;
		}else{
			//NSLog(@"Unable to find ': ' that seperates key and value in %@", obj);
		}
	}];
}

#pragma mark Conversion Methods
#pragma mark GNTP to Growl
+(NSDictionary*)gntpToGrowlMatchingDict {
	static NSDictionary *_matchingDict = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_matchingDict = [[NSDictionary dictionaryWithObjectsAndKeys:GROWL_APP_NAME, GrowlGNTPApplicationNameHeader,
								GROWL_APP_ICON_DATA, GrowlGNTPApplicationIconHeader,
								GROWL_NOTIFICATION_ICON_DATA, GrowlGNTPNotificationIcon,
								GROWL_NOTIFICATION_IDENTIFIER, @"Notification-Coalescing-ID",
								GROWL_NOTIFICATION_INTERNAL_ID, GrowlGNTPNotificationID,
								GROWL_NOTIFICATION_NAME, GrowlGNTPNotificationName,
								GROWL_NOTIFICATION_TITLE, GrowlGNTPNotificationTitle,
								GROWL_NOTIFICATION_DESCRIPTION, GrowlGNTPNotificationText,
								GROWL_NOTIFICATION_STICKY, GrowlGNTPNotificationSticky,
								GROWL_NOTIFICATION_PRIORITY, GrowlGNTPNotificationPriority,
								GROWL_NOTIFICATION_CALLBACK_URL_TARGET, GrowlGNTPNotificationCallbackTarget,
								GROWL_NOTIFICATION_GNTP_RECEIVED, @"Received",
								GROWL_NOTIFICATION_GNTP_SENT_BY, @"Sent-By",
								GROWL_GNTP_ORIGIN_MACHINE, GrowlGNTPOriginMachineName,
								GROWL_GNTP_ORIGIN_SOFTWARE_NAME, GrowlGNTPOriginSoftwareName,
								GROWL_GNTP_ORIGIN_SOFTWARE_VERSION, GrowlGNTPOriginSoftwareVersion,
								GROWL_GNTP_ORIGIN_PLATFORM_NAME, GrowlGNTPOriginPlatformName,
								GROWL_GNTP_ORIGIN_PLATFORM_VERSION, GrowlGNTPOriginPlatformVersion, nil] retain];
	});
	return _matchingDict;
}
+(NSString*)growlDictKeyForGNTPKey:(NSString*)gntpKey {
	if([[GNTPPacket gntpToGrowlMatchingDict] objectForKey:gntpKey])
		return [[GNTPPacket gntpToGrowlMatchingDict] objectForKey:gntpKey];
	return gntpKey;
}
+(id)convertedObjectFromGNTPObject:(id)obj forGrowlKey:(NSString*)growlKey {
	id convertedObj = obj;
	if([growlKey isEqualToString:GROWL_NOTIFICATION_STICKY]){
		if([obj caseInsensitiveCompare:@"Yes"] == NSOrderedSame || 
			[obj caseInsensitiveCompare:@"True"] == NSOrderedSame)
		{
			convertedObj = [NSNumber numberWithBool:YES];
		}else {
			convertedObj = [NSNumber numberWithBool:YES];
		}
	}else if([growlKey isEqualToString:GROWL_NOTIFICATION_PRIORITY]){
		convertedObj = [NSNumber numberWithInteger:[obj integerValue]];
	}else if([growlKey isEqualToString:GROWL_APP_ICON_DATA] ||
				[growlKey isEqualToString:GROWL_NOTIFICATION_ICON_DATA])
	{
		if([obj isKindOfClass:[NSString class]]){
			NSURL *url = [NSURL URLWithString:obj];
			if(url)
				convertedObj = [NSData dataWithContentsOfURL:url];
			else
				NSLog(@"Icon String: %@ is not a URL, and was not retrieved by the packet as a resource", obj);
		}//There is no else, either its already data, or we dont know what to do with it
	}
	return convertedObj;
}
#pragma mark Growl to GNTP
+(NSDictionary*)growlToGNTPMatchingDict {
	static NSDictionary *_matchingDict = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_matchingDict = [[NSDictionary dictionaryWithObjectsAndKeys:GrowlGNTPApplicationNameHeader, GROWL_APP_NAME,
								GrowlGNTPApplicationIconHeader, GROWL_APP_ICON_DATA,
								GrowlGNTPNotificationIcon, GROWL_NOTIFICATION_ICON_DATA,
								@"Notification-Coalescing-ID", GROWL_NOTIFICATION_IDENTIFIER,
								GrowlGNTPNotificationID, GROWL_NOTIFICATION_INTERNAL_ID,
								GrowlGNTPNotificationName, GROWL_NOTIFICATION_NAME,
								GrowlGNTPNotificationTitle, GROWL_NOTIFICATION_TITLE,
								GrowlGNTPNotificationText, GROWL_NOTIFICATION_DESCRIPTION,
								GrowlGNTPNotificationSticky, GROWL_NOTIFICATION_STICKY,
								GrowlGNTPNotificationPriority, GROWL_NOTIFICATION_PRIORITY,
								GrowlGNTPNotificationCallbackTarget, GROWL_NOTIFICATION_CALLBACK_URL_TARGET,
								@"Received", GROWL_NOTIFICATION_GNTP_RECEIVED,
								@"Sent-By", GROWL_NOTIFICATION_GNTP_SENT_BY,
								GrowlGNTPOriginMachineName, GROWL_GNTP_ORIGIN_MACHINE,
								GrowlGNTPOriginSoftwareName, GROWL_GNTP_ORIGIN_SOFTWARE_NAME,
								GrowlGNTPOriginSoftwareVersion, GROWL_GNTP_ORIGIN_SOFTWARE_VERSION,
								GrowlGNTPOriginPlatformName, GROWL_GNTP_ORIGIN_PLATFORM_NAME,
								GrowlGNTPOriginPlatformVersion, GROWL_GNTP_ORIGIN_PLATFORM_VERSION,
								@"Connection", @"Connection", nil] retain];
	});
	return _matchingDict;
}
+(NSString*)gntpKeyForGrowlDictKey:(NSString*)growlKey {
	if([[self growlToGNTPMatchingDict] objectForKey:growlKey])
		return [[self growlToGNTPMatchingDict] objectForKey:growlKey];
	return nil;
}
+(id)convertedObjectFromGrowlObject:(id)obj forGNTPKey:(NSString*)gntpKey {
	if([obj isKindOfClass:[NSString class]])
		return obj;
	id converted = nil;
	if([gntpKey caseInsensitiveCompare:GrowlGNTPApplicationIconHeader] == NSOrderedSame ||
				[gntpKey caseInsensitiveCompare:GrowlGNTPNotificationIcon] == NSOrderedSame)
	{
		if([obj isKindOfClass:[NSData class]])
			converted = obj;
		else if([obj isKindOfClass:[NSURL class]])
			converted = [obj absoluteString];
		//There is no else, either its already data, or we dont know what to do with it
	}else if([gntpKey caseInsensitiveCompare:@"Connection"] == NSOrderedSame){
		if([obj boolValue])
			converted = @"Keep-Alive";
		else
			converted = @"Close";
	}else if([gntpKey isEqualToString:@"Received"]){
		converted = obj;
	}
	return converted;
}

#pragma mark Packet Building
+(NSDictionary*)growlDictFilledInForConversion:(NSDictionary*)growlDict {
	/* Ensure we have all the nesescary headers as Growl headers
	 * Things that might be missing:
	 * computer id info
	 * internal id
	 * Connection type
	 */
	return growlDict;
}
+(NSMutableDictionary*)gntpDictFromGrowlDict:(NSDictionary*)dict {
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	[dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		NSString *gntpKey = [self gntpKeyForGrowlDictKey:key];
		if(gntpKey){
			id convertedValue = [self convertedObjectFromGrowlObject:obj forGNTPKey:gntpKey];
			if(convertedValue){
				if([convertedValue isKindOfClass:[NSString class]]){
					//stuff in the regular header
					[dictionary setObject:convertedValue forKey:gntpKey];
				}else if([convertedValue isKindOfClass:[NSData class]]){
					//stuff a header into the binary header
					NSString *dataIdentifier = [self identifierForBinaryData:convertedValue];
					NSMutableDictionary *dataDict = [dictionary objectForKey:@"GNTPDATABLOCKS"];
					if(!dataDict){
						dataDict = [NSMutableDictionary dictionary];
						[dictionary setObject:dataDict forKey:@"GNTPDATABLOCKS"];
					}
					[dataDict setObject:convertedValue forKey:dataIdentifier];
					[dictionary setObject:[NSString stringWithFormat:@"x-growl-resource://%@", dataIdentifier] forKey:gntpKey];
				}else if([gntpKey caseInsensitiveCompare:@"Received"] == NSOrderedSame){
					[dictionary setObject:convertedValue forKey:@"Received"];
				}else{
					NSLog(@"%@ for key %@ is an unknown data type for putting in a GNTP dictioanry", convertedValue, gntpKey);
				}
			}
		}
	}];
	return dictionary;
}
+(NSString*)headersForGNTPDictionary:(NSDictionary*)dict {
	__block NSMutableString *headerBlock = [NSMutableString string];
	[dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		if(![key isEqualToString:@"GNTPDATABLOCKS"]){
			if([obj isKindOfClass:[NSString class]])
				[headerBlock appendFormat:@"%@: %@\r\n", key, obj];
			else if([key isEqualToString:@"Received"]){
				[obj enumerateObjectsUsingBlock:^(id innerObj, NSUInteger idx, BOOL *innerStop) {
					[headerBlock appendFormat:@"Received: %@\r\n", innerObj];
				}];
			}
		}
	}];
	return [[headerBlock copy] autorelease];
}
+(NSData*)gntpDataFromGrowlDictionary:(NSDictionary*)growlDict 
										 ofType:(NSString*)type
										withKey:(GNTPKey*)encryptionKey
{
	NSDictionary *gntpDict = [self gntpDictFromGrowlDict:[self growlDictFilledInForConversion:growlDict]];
	BOOL encrypt = [encryptionKey encryptionAlgorithm] != GNTPNone;
	
	NSMutableString *packetString = [NSMutableString stringWithFormat:@"GNTP/1.0 %@ %@", type, [encryptionKey encryption]];
	if([encryptionKey hashAlgorithm] != GNTPNoHash){
		[packetString appendFormat:@" %@", [encryptionKey key]];
	}
	[packetString appendString:@"\r\n"];
	
	NSMutableData *packetData = [[packetString dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
	NSString *headers = [self headersForGNTPDictionary:gntpDict];
	//Encrypt them if need be
	NSData *headerData = [headers dataUsingEncoding:NSUTF8StringEncoding];
	if(encrypt)
		[packetData appendData:[encryptionKey encrypt:headerData]];
	else
		[packetData appendData:headerData];
	[packetData appendData:[GCDAsyncSocket CRLFData]];
	//NSLog(@"%@\r\n%@", packetString, headers);
	
	NSMutableDictionary *dataBlocks = [gntpDict objectForKey:@"GNTPDATABLOCKS"];
	if(dataBlocks){
		[dataBlocks enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
			NSData *encrypted = obj;
			if(encrypt)
				encrypted = [encryptionKey encrypt:obj];
			
			NSMutableString *header = [NSMutableString stringWithFormat:@"Identifier: %@\r\nLength: %lu\r\n\r\n", key, [encrypted length]];
			[packetData appendData:[header dataUsingEncoding:NSUTF8StringEncoding]];
			[packetData appendData:encrypted];
			[packetData appendData:[GNTPUtilities doubleCRLF]];
		}];
	}
	if([[gntpDict valueForKey:@"Connection"] isEqualToString:@"Keep-Alive"])
		[packetData appendData:[GNTPUtilities gntpEndData]];
	return packetData;
}

+ (NSString *)identifierForBinaryData:(NSData *)data
{
	unsigned char *digest = malloc(sizeof(unsigned char)*CC_MD5_DIGEST_LENGTH);
	CC_MD5([data bytes], (unsigned int)[data length], digest);
	NSString *identifier = [NSString stringWithFormat: @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
									digest[0], digest[1], 
									digest[2], digest[3],
									digest[4], digest[5],
									digest[6], digest[7],
									digest[8], digest[9],
									digest[10], digest[11],
									digest[12], digest[13],
									digest[14], digest[15]];
	free(digest);
	return identifier;	
}

#pragma mark Incoming packet instance methods
-(id)init {
	if((self = [super init])){
		_gntpDictionary = [[NSMutableDictionary alloc] init];
		_dataBlockIdentifiers = [[NSMutableArray alloc] init];
		_state = 0;
		_incomingDataLength = 0;
		_incomingDataHeaderRead = NO;
		_incomingDataIdentifier = nil;
		self.keepAlive = NO;
	}
	return self;
}

-(void)dealloc {
	self.growlDict = nil;
	self.gntpDictionary = nil;
	self.dataBlockIdentifiers = nil;
	self.incomingDataIdentifier = nil;
	self.key = nil;
	[super dealloc];
}

-(NSInteger)parsePossiblyEncryptedDataBlock:(NSData*)data {
	if([self.key encryptionAlgorithm] == GNTPNone)
		return [self parseDataBlock:data];
	
	NSData *decryptedData = data;
	NSInteger result = -1;
	switch (self.state) {
		//Initial Headers, could include registration
		case 0:
		{
			decryptedData = [self.key decrypt:data];
			NSString *allHeaders = [NSString stringWithUTF8String:[decryptedData bytes]];
			NSMutableArray *portions = [[[allHeaders componentsSeparatedByString:@"\r\n\r\n"] mutableCopy] autorelease];
			if([portions count] > 0) {
				do {
					NSString *current = [portions objectAtIndex:0];
					result = [self parseDataBlock:[NSData dataWithBytes:[current UTF8String] length:[current length]]];
					[portions removeObjectAtIndex:0];
				} while (result > 0 && [portions count] > 0);
			}else
				result = -1;
			break;
		}
		//Data blocks
		case 2:
			if([data length] != self.incomingDataLength)
				NSLog(@"Gah! Read data block and stated data length not the same!");
			result = [self parseDataBlock:[self.key decrypt:data]];
			break;
		//Everything else
		case 1:			
		default:
			result = [self parseDataBlock:data];
			break;
	}
	return result;
}

-(NSInteger)parseDataBlock:(NSData*)data {
	NSInteger result = 0;
	__block GNTPPacket *blockSelf = self;
	switch (_state) {
		case 0:
		{
			//Our initial header block
			NSString *headersString = [NSString stringWithUTF8String:[data bytes]];
			[GNTPPacket enumerateHeaders:headersString 
									 withBlock:^BOOL(NSString *headerKey, NSString *headerValue) {
										 [blockSelf parseHeaderKey:headerKey value:headerValue];
										 return NO;
									 }];
			result = [self.dataBlockIdentifiers count];
			if(result == 0)
				self.state = 999;
			else
				self.state = 1;
			break;
		}
		case 1:
			//Reading in a header for data blocks
			if(self.incomingDataHeaderRead){
				NSLog(@"Error! Should never be in this state thinking a header has been read");
				result = -1;
				break;
			}
			
			[self parseResourceDataHeader:data];
			if(self.incomingDataHeaderRead){
				self.state = 2;
				result = 1;
			}else{
				result = -1;
				NSLog(@"Unable to validate data block header");
				break;
			}
			break;
		case 2:
			//Reading in a data block
			if(!self.incomingDataHeaderRead){
				NSLog(@"Error! Should never be in this state thinking a header has not been read");
				result = -1;
				break;
			}
			[self parseResourceDataBlock:data];
			
			result = [self.dataBlockIdentifiers count];
			if([self.dataBlockIdentifiers count] == 0){
				self.state = 999;
			}else{
				self.incomingDataHeaderRead = NO;
				self.state = 1;
				self.incomingDataLength = 0;
				self.incomingDataIdentifier = nil;
			}
			break;
		case 999:
			result = 0;
			break;
		default:
			NSLog(@"OH NOES! Unknown State in main parser");
			break;
	}
	return result;
}

-(void)parseHeaderKey:(NSString*)headerKey value:(NSString*)stringValue {
	//If there are any special case generic keys, handle them here
	NSRange resourceRange = [stringValue rangeOfString:@"x-growl-resource://"];
	if(resourceRange.location != NSNotFound && resourceRange.location == 0){
		//This is a resource ID; add the ID to the array of waiting IDs
		NSString *dataBlockID = [stringValue substringFromIndex:resourceRange.location + resourceRange.length];
		[self.dataBlockIdentifiers addObject:dataBlockID];
		[self.gntpDictionary setObject:stringValue forKey:headerKey];
	}else if([headerKey caseInsensitiveCompare:@"CONNECTION"] == NSOrderedSame){
		//We need to setup keep alive here
		if([stringValue caseInsensitiveCompare:@"Keep-Alive"] == NSOrderedSame)
			self.keepAlive = YES;
		else
			self.keepAlive = NO;
	}else if([headerKey caseInsensitiveCompare:@"Received"] == NSOrderedSame){
		NSMutableArray *receivedValues = [self.gntpDictionary valueForKey:headerKey];
		if (!receivedValues) {
			receivedValues = [NSMutableArray array];
			[self.gntpDictionary setObject:receivedValues
											forKey:headerKey];
		}
		[receivedValues addObject:stringValue];
	}else{
		[self.gntpDictionary setObject:stringValue forKey:headerKey];
	}
}

-(void)parseResourceDataHeader:(NSData*)data {
	NSString *headersString = [NSString stringWithUTF8String:[data bytes]];
	__block NSString *newId = nil;
	__block NSString *newLength = nil;
	[GNTPPacket enumerateHeaders:headersString 
							 withBlock:^BOOL(NSString *headerKey, NSString *headerValue) {
								 if([headerKey caseInsensitiveCompare:@"Identifier"] == NSOrderedSame){
									 newId = [headerValue retain];
								 }else if([headerKey caseInsensitiveCompare:@"Length"] == NSOrderedSame){
									 newLength = [headerValue retain];
								 }else {
									 //NSLog(@"No other headers we care about here");
								 }
								 if(newId && newLength)
									 return YES;
								 return NO;
							 }];
	if(!newId || !newLength){
		NSLog(@"Error! Could not find id and length in header");
	}else{
		self.incomingDataHeaderRead = YES;
		self.incomingDataIdentifier = newId;
		self.incomingDataLength = [newLength integerValue];
	}
	[newId release];
	[newLength release];
}

-(void)parseResourceDataBlock:(NSData*)data {
	[self receivedResourceDataBlock:data forIdentifier:self.incomingDataIdentifier];
	[self.dataBlockIdentifiers removeObject:self.incomingDataIdentifier];
}

-(void)receivedResourceDataBlock:(NSData*)data forIdentifier:(NSString*)identifier {
	__block NSMutableArray *keysToReplace = [NSMutableArray array];
	[self.gntpDictionary enumerateKeysAndObjectsUsingBlock:^(id aKey, id obj, BOOL *stop) {
		if([obj isKindOfClass:[NSString class]]){
			NSRange resourceRange = [obj rangeOfString:@"x-growl-resource://"];
			if(resourceRange.location != NSNotFound && resourceRange.location == 0){
				NSString *dataBlockID = [obj substringFromIndex:resourceRange.location + resourceRange.length];
				if([identifier isEqualToString:dataBlockID]){
					[keysToReplace addObject:aKey];
				}
			}
		}
	}];
	[keysToReplace enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		[self.gntpDictionary setObject:data forKey:obj];
	}];
}

-(BOOL)validate {
	return YES;
}
-(NSString*)responseString {
	return [NSString stringWithFormat:@"GNTP/1.0 -OK NONE\r\nResponse-Action: %@\r\n\r\n", self.action];
}
-(NSData*)responseData {
	NSString *responseString = [self responseString];
	return [NSData dataWithBytes:[responseString UTF8String] length:[responseString length]];
}
-(NSTimeInterval)requestedTimeAlive {
	NSTimeInterval result = 0.0;
	if(self.keepAlive)
		result = 15.0;
	return result;
}

-(NSMutableDictionary*)convertedGrowlDict {
	NSMutableDictionary *convertedDict = [NSMutableDictionary dictionary];
	[self.gntpDictionary enumerateKeysAndObjectsUsingBlock:^(id gntpKey, id obj, BOOL *stop) {
		NSString *growlDictKey = [GNTPPacket growlDictKeyForGNTPKey:gntpKey];
		if(!growlDictKey){
			//If there isn't a growl dict key, just stuff the object in there normal like
			[convertedDict setObject:obj forKey:gntpKey];
		}else{
			id convertedObj = [GNTPPacket convertedObjectFromGNTPObject:obj forGrowlKey:growlDictKey];
			[convertedDict setObject:convertedObj forKey:growlDictKey];
		}
	}];
	//Give it an internal ID regardless
	if(![convertedDict objectForKey:GROWL_NOTIFICATION_INTERNAL_ID])
		[convertedDict setObject:[[NSProcessInfo processInfo] globallyUniqueString] forKey:GROWL_NOTIFICATION_INTERNAL_ID];
	[convertedDict setObject:self.guid forKey:@"GNTPGUID"];
	[convertedDict setObject:[NSNumber numberWithBool:self.keepAlive] forKey:@"GNTP-Keep-Alive"];
	return convertedDict;
}
-(NSDictionary*)growlDict {
	if(!_growlDict){
		_growlDict = [[self convertedGrowlDict] copy];
	}
	return _growlDict;
}

@end