//
//  GrowlNotificationHistoryWindow.m
//  Growl
//
//  Created by Daniel Siemer on 9/2/10.
//  Copyright 2010 The Growl Project. All rights reserved.
//

#import "GrowlNotificationHistoryWindow.h"
#import "GrowlNotificationDatabase.h"
#import "GrowlHistoryNotification.h"

@implementation GrowlNotificationHistoryWindow

@synthesize historyTable;
@synthesize arrayController;
@synthesize awayDate;

-(id)init
{
   if((self = [super initWithWindowNibName:@"AwayHistoryWindow" owner:self]))
   {

   }
   return self;
}

-(void)dealloc
{
   [historyTable release]; historyTable = nil;
   [arrayController release]; historyTable = nil;
   historyController = nil;
   
   [awayDate release]; awayDate = nil;
   
   [super dealloc];
}

-(void)windowWillLoad
{

}

-(void)windowDidLoad
{
}


-(void)windowWillClose:(NSNotification *)notification
{
   [[GrowlNotificationDatabase sharedInstance] userReturnedAndClosedList];
}

-(void)showWindow:(id)sender
{
   [historyTable noteNumberOfRowsChanged];
   [super showWindow:sender];
}

-(void)resetArrayWithDate:(NSDate*)newAway
{
   self.awayDate = newAway;

   NSError *error = nil;
   [arrayController setFetchPredicate:[NSPredicate predicateWithFormat:@"Time >= %@ AND Time <= %@", awayDate, [NSDate date]]];
   [arrayController fetchWithRequest:[arrayController defaultFetchRequest] merge:NO error:&error];
   if (error)
      NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
}

-(GrowlNotificationDatabase*)historyController
{
   if(!historyController)
      historyController = [GrowlNotificationDatabase sharedInstance];
      
   return historyController;
}

#pragma mark -
#pragma mark GrowlDatabaseUpdateDelegate methods

-(BOOL)CanGrowlDatabaseHardReset:(GrowlAbstractDatabase*)db
{
   return NO;
}

-(void)GrowlDatabaseDidUpdate:(GrowlAbstractDatabase*)db
{

}

@end