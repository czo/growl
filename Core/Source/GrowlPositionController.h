//
//  GrowlPositionController.h
//  Growl
//
//  Created by Ofri Wolfus on 31/08/05.
//  Copyright 2004-2006 The Growl Project. All rights reserved.
//
// This file is under the BSD License, refer to License.txt for details
//

/*!
 * @header GrowlPositionController
 * GrowlPositionController provides a mechanism for display plugins to display without disturbing each other.
 * @copyright Created by Ofri Wolfus on 31/08/05. Copyright 2004-2006 The Growl Project. All rights reserved.
 * @updated 2005-09-18
 * @version 0.8
 */

@class GrowlDisplayWindowController;

#import "GrowlAbstractSingletonObject.h"
#import "GrowlPositioningDefines.h"

extern NSString *NSStringFromGrowlPosition(enum GrowlPosition pos);

extern NSString *NSStringFromGrowlExpansionDirection(enum GrowlExpansionDirection dir);

/*!
 * @class GrowlPositionController
 * @superclass GrowlAbstractSingletonObject
 * @abstract GrowlPositionController provides a mechanism for display plugins to display without disturbing each other.
 * @discussion GrowlPositionController prevents notifications from covering each other by reserving a rect on the screen which contains the notification.
 * When a rect is reserved, no other notification should be displayed inside this rect (although plugins may ignore this rule).
 * Before a notification is displayed, the display plugin should reserve the rect it's going to use, and clear it when it is done with it.
 * Plugins that uses GrowlDisplayWindowController don't need to worry about contacting GrowlPositionController and reserving rects.
 * GrowlDisplayWindowController takes care for it, but it does require the display plugin to relocate the notification, and display it again.
 */
@interface GrowlPositionController : GrowlAbstractSingletonObject {
	int selectedPositionType;
	enum GrowlPositionOrigin selectedCustomPosition;
	CFMutableDictionaryRef	reservedRects;
}

/*!
 * @method rectForPosition:inScreen:
 * @abstract Returns a rect for a specific position in a specific screen. The rect's size is depended on the resolution and the size of the screen.
 * @param position The position in the specific screen.
 * @param screen The screen which contains the rect of the position. If screen is nil, the main screen will be used.
 */
+ (NSRect) rectForPosition:(enum GrowlPosition)position inScreen:(NSScreen *)screen;

/*!
 * @method selectedOriginPosition
 * @abstract Reads in the stored selection from picker and translate to a properly returned GrowlPosition.
 * @result GrowlPosition enum. Contains the selected position of one of the enumerated options as translated from the position picker's selection.
 */
+ (enum GrowlPosition)selectedOriginPosition;

- (BOOL) positionDisplay:(GrowlDisplayWindowController *)displayController;

/*!
 * @method reserveRect:inScreen:
 * @abstract Reserves a rect for a notification in a specific screen.
 * @discussion Reserves a rect for a notification.
 * Before a notification is displayed, it should reserve the rect of screen it's going to use.
 * When a rect is reserved, no other notification can use it so you must clear it when you're done with it.
 * A rect will fail to be reserved in the following cases:
 * 1. inRect is not completely inside inScreen.
 * 2. inRect intersects with an already reserved rect.
 * @param inRect The rect that should be reserved.
 * @param inScreen The screen which contains inRect. If inScreen is nil, the main screen will be used.
 * @result YES or NO. If the result is NO, you should display your notification in a different rect/screen.
 */
- (BOOL) reserveRect:(NSRect)inRect inScreen:(NSScreen *)inScreen;

/*!
 * @method clearReservedRect:inScreen:
 * @abstract Clear a reserved notification rect.
 * @param inRect The reserved rect that should be cleared.
 * @param inScreen The screen which contains inRect. If inScreen is nil, the main screen will be used.
 */
- (void) clearReservedRect:(NSRect)inRect inScreen:(NSScreen *)inScreen;

- (enum GrowlPosition) originPosition;

@end

#pragma mark -

@interface NSObject (GrowlPositionControllerProtocol)

/* for the time being this is a simplified version of the protocol.  the finished iteration should take
 * into account screen number as well as the types of adjoining displays */

- (NSPoint) idealOriginInRect:(NSRect)rect;
- (enum GrowlExpansionDirection) primaryExpansionDirection;
- (enum GrowlExpansionDirection) secondaryExpansionDirection;
- (float) requiredDistanceFromExistingDisplays;

@end
