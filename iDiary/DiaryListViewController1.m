//
//  DiaryListViewController.m
//  iDiary
//
//  Created by chenshun on 12-11-16.
//  Copyright (c) 2012年 ChenShun. All rights reserved.
//

#import "DiaryListViewController.h"
#import "DiaryContentViewController.h"
#import "SystemSettingViewController.h"
#import "CommmonMethods.h"
#import "DiaryDescription.h"
#import "NoteDocument.h"

#import "NSDateAdditions.h"
#import "FilePath.h"
#import "PasswordViewController.h"
#import "NSDate+FormattedStrings.h"

NSString *const TDDocumentsDirectoryName = @"Documents";
NSString *const HTMLExtentsion = @".html";
const NSInteger ActionSheetDelete = 1020;
const NSInteger ActionSheetShare = 1021;

@interface DiaryListViewController ()
{    
    NoteDocument *document;
    
    DocumentsAccess *docAccess;
    NSInteger fileCount;
    
    NSIndexPath *indexPathToDel;
    NSIndexPath *indexPathToShare;
}
@property (nonatomic, retain)NSIndexPath *indexPathToShare;
@property (nonatomic, retain)NSIndexPath *indexPathToDel;
@property (nonatomic, retain)NSURL *iCloudRoot;
@property (nonatomic, retain) NoteDocument *document;
- (void)reloadNotes:(BOOL)needReload;
- (void)loadLocalNotes;
- (void)addOrUpdateEntryWithURL:(NSURL *)fileURL
                       metadata:(Metadata *)metadata
                          state:(UIDocumentState)state
                        version:(NSFileVersion *)version
                     needReload:(BOOL)reload;
- (int)indexOfEntryWithFileURL:(NSURL *)fileURL;
@end

@implementation DiaryListViewController
@synthesize mTableView;
@synthesize tmpCell, cellNib;
@synthesize deleteButton, addButton, cancelButton, editButton, settingsButton, toolbar;
@synthesize iCloudRoot;
@synthesize document;
@synthesize indexPathToDel, indexPathToShare;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = NSLocalizedString(@"Diary", @"");
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [entityArray release];
    [mTableView release];
    [tmpCell release];
    [cellNib release];

    [deleteButton release];
    [addButton release];
    [cancelButton release];
    [editButton release];
    [toolbar release];
    [settingsButton release];
    
    [iCloudRoot release];
    [docAccess release];
    [document release];
    [indexPathToDel release];
    [indexPathToShare release];
    [super dealloc];
}


#pragma mark View cycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.mTableView.rowHeight = 100;
    self.mTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    fileCount = 0;
    
    //cell的背景颜色和tableview的一样
    self.mTableView.backgroundColor = HEXCOLOR(0xf0f7ff, 1.0);
    self.view.backgroundColor = HEXCOLOR(0xf0f7ff, 1.0);
    
    self.cellNib = [UINib nibWithNibName:@"AdvancedCell" bundle:nil];
    self.navigationItem.rightBarButtonItem = self.addButton;
   // self.navigationItem.leftBarButtonItem = self.settingsButton;
   // [self.addButton setImage:[UIImage imageNamed:@"new.png"]];
   // [self.settingsButton setImage:[UIImage imageNamed:@"setting.png"]];
//    UIImage *backButtonImage = [[UIImage imageNamed:@"barButtonBK.png"] resizableImageWithCapInsets:UIEdgeInsetsMake(0,15,0,6)];
//    [self.navigationItem.leftBarButtonItem setBackgroundImage:backButtonImage forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
//    [self.navigationItem.rightBarButtonItem setBackgroundImage:backButtonImage forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    
    self.navigationItem.title = NSLocalizedString(@"Diary", nil);

    UIBarButtonItem *temporaryBarButtonItem = [[UIBarButtonItem alloc] init];
	temporaryBarButtonItem.title = NSLocalizedString(@"Back", nil);
 	self.navigationItem.backBarButtonItem = temporaryBarButtonItem;
	[temporaryBarButtonItem release];

    entityArray = [[NSMutableArray alloc] init];
    
    self.mTableView.allowsSelectionDuringEditing = YES;
    
    [self reloadNotes:YES];
    
    mySocial = [[TTSocial alloc] init];
    mySocial.viewController = self;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(documentStateChange:)
                                                 name:UIDocumentStateChangedNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(dataSourceChanged:)
                                                 name:@"DataSourceChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(storageLocationChanged:)
                                                 name:@"StorageLocationChanged" object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)didBecomeActive:(NSNotification *)notification
{
    if (docAccess != nil)
    {
        if ([docAccess iCloudOn])
        {
            [self reloadNotes:YES];
        }
    }
}

- (void)didResignActive:(NSNotification *)notification
{
    if (docAccess != nil)
    {
        if ([docAccess iCloudOn])
        {
            //[docAccess stopQuery];
        }
    }
}

- (void)resolveConfict:(NSURL *)url
{
    // newest version wins
    [NSFileVersion removeOtherVersionsOfItemAtURL:url error:nil];
    NSArray* conflictVersions = [NSFileVersion unresolvedConflictVersionsOfItemAtURL:url];
    for (NSFileVersion* fileVersion in conflictVersions) {
        fileVersion.resolved = YES;
    }
}

- (void)documentStateChange:(NSNotification *)notification
{
    UIDocument *doc = (UIDocument *)notification.object;
    if (doc != nil)
    {
        UIDocumentState state = doc.documentState;
        if (state & UIDocumentStateInConflict)
        {
            [self resolveConfict:doc.fileURL];
        }
    }
}

- (void)dataSourceChanged:(NSNotification *)notification
{
    DocEntity *entity = (DocEntity *)[notification object];
    if (entity != nil)
    {
        int index = [self indexOfEntryWithFileURL:entity.docURL];
        if (index >= 0)
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [self.mTableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil]
                                   withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        else
        {
            [entityArray insertObject:entity atIndex:0];
            [self.mTableView insertRowsAtIndexPaths:[NSArray arrayWithObjects:[NSIndexPath indexPathForRow:0 inSection:0], nil] 
                                   withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
}

- (void)updataDataSource:(NSArray *)urlArray
{
    NSURL *iCloudDocURL = [docAccess iCloudDocURL];
    int nCount = [entityArray count];
    [entityArray enumerateObjectsUsingBlock:^(DocEntity * entry, NSUInteger idx, BOOL *stop) 
    {
        if (idx < nCount)
        {
            NSString *fileName = entry.docURL.lastPathComponent;
            entry.docURL = [iCloudDocURL URLByAppendingPathComponent:fileName];
            
            NSLog(@"updataDataSource %@", entry.docURL);
        }
        else
        {
            *stop = YES;
        }
    }];
}

- (void)storageLocationChanged:(NSNotification *)notification
{
    [self reloadNotes:YES];
}

- (void)reloadNotes:(BOOL)needReload
{
    if (needReload)
    {
        [entityArray removeAllObjects];
    }
    
    if (docAccess == nil)
    {
        docAccess = [[DocumentsAccess alloc] initWithDelegate:self];
    }
    
    [docAccess initializeiDocAccess:^(BOOL available){
    
        if (available)
        {
            // 询问是否把数据存入ICLOUD, 并且是在没有提示过的情况下,如果提示过了下次就不再提示
            if (![docAccess iCloudOn] && ![docAccess iCloudPrompted])
            {
                // 设置为提示过
                [docAccess setiCloudPrompted:YES];
//                UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"iCloud is Available" 
//                                                                     message:@"Automatically store your documents in the cloud to keep them up-to-date across all your devices and the web." 
//                                                                    delegate:self 
//                                                           cancelButtonTitle:@"Later" 
//                                                           otherButtonTitles:@"Use iCloud", nil];
//                alertView.tag = 1;
//                [alertView show];
                [docAccess setiCloudOn:YES];
                [self reloadNotes:YES];
            }
            
            // move iCloud docs to local
            if (![docAccess iCloudOn] && [docAccess iCloudWasOn])
            {
                [docAccess iCloudToLocal:kNotePacketExtension completion:^(NSArray *fileArray){
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        [self loadLocalNotes];
                    });
                }];
            }
            
            // move local docs to iCloud
            if ([docAccess iCloudOn] && ![docAccess iCloudWasOn])
            {
                [docAccess localToiCloud:kNotePacketExtension completion:^(NSArray *fileArray){
                     
                    dispatch_async(dispatch_get_main_queue(), ^{
                        
                        [self updataDataSource:fileArray];
                    });
                }]; 
               
            }
            
            if ([docAccess iCloudOn] && needReload)
            {
                NSString * filePattern = [NSString stringWithFormat:@"*.%@", kNotePacketExtension];
                [docAccess startQueryForPattern:filePattern];
            }

            // No matter what, refresh with current value of iCloudOn
            [docAccess setiCloudWasOn:[docAccess iCloudOn]];
        }
        else
        {
            // If iCloud isn't available, set promoted to no (so we can ask them next time it becomes available)
            [docAccess setiCloudPrompted:NO];
            
            // If iCloud was toggled on previously, warn user that the docs will be loaded locally
            if ([docAccess iCloudWasOn]) {
                UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"You're Not Using iCloud" message:@"Your documents were removed from this iPhone but remain stored in iCloud." delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
                [alertView show];
            }
            
            // No matter what, iCloud isn't available so switch it to off.
            [docAccess setiCloudOn:NO]; 
            [docAccess setiCloudWasOn:NO];
        }
        
        // 查询本地
        if (![docAccess iCloudOn] && needReload)
        {
            [self loadLocalNotes];
        }
    }];
}

- (void)loadLocalNotes
{
    [entityArray removeAllObjects];
    NSURL *localDocURL = [FilePath localDocumentsDirectoryURL];
    NSArray * localDocuments = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:localDocURL
                                                             includingPropertiesForKeys:nil 
                                                                                options:0 
                                                                                  error:nil];
    fileCount = [localDocuments count];
    for (int i=0; i < fileCount; i++)
    {
        NSURL * fileURL = [localDocuments objectAtIndex:i];

        
        if ([[fileURL pathExtension] isEqualToString:kNotePacketExtension])
        {
            [self addOrUpdateEntryWithURL:fileURL metadata:nil state:UIDocumentStateNormal version:nil needReload:NO];
        }
    }
    
    [FilePath sortUsingDescending:entityArray];
    [self.mTableView reloadData];
}

- (int)indexOfEntryWithFileURL:(NSURL *)fileURL 
{
    __block int retval = -1;
    [entityArray enumerateObjectsUsingBlock:^(DocEntity * entry, NSUInteger idx, BOOL *stop) {
        if ([entry.docURL isEqual:fileURL]) {
            retval = idx;
            *stop = YES;
        }
    }];
    return retval;    
}

- (void)addOrUpdateEntryWithURL:(NSURL *)fileURL
                       metadata:(Metadata *)metadata
                          state:(UIDocumentState)state
                        version:(NSFileVersion *)version
                     needReload:(BOOL)reload
{
    DocEntity *entity = nil;
    int index = [self indexOfEntryWithFileURL:fileURL];
    if (index >= 0)
    {
        entity = [entityArray objectAtIndex:index];
        entity.metadata = metadata;
        entity.state = state;
        entity.version = version;
        if (reload)
        {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            [self.mTableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] 
                                   withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
    else
    {
        entity = [[[DocEntity alloc] initWithFileURL:fileURL
                                                      metadata:metadata
                                                         state:state
                                                       version:version] autorelease];
        [entityArray insertObject:entity atIndex:0];
        if (reload)
        {
            [self.mTableView insertRowsAtIndexPaths:[NSArray arrayWithObjects:[NSIndexPath indexPathForRow:0 inSection:0], nil] 
                                   withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    }
}

- (IBAction)systemSetting:(id)sender
{
    SystemSettingViewController *systemSettingViewController = [[SystemSettingViewController alloc] initWithNibName:@"SystemSettingViewController"
                                                                                                             bundle:nil];
    //[self presentModalViewController:systemSettingViewController animated:YES];
    [self.navigationController pushViewController:systemSettingViewController animated:YES];
    [systemSettingViewController release];
}

- (IBAction)addAction:(id)sender
{
    NSString *wrapperName = [FilePath generateFileNameBy:[NSDate date] extension:kNotePacketExtension];
    NSURL *wrapperURL = nil;

    if (docAccess.iCloudAvailable && [docAccess iCloudOn])
    {
        NSURL *cloudRootURL = [docAccess.ubiquityURL URLByAppendingPathComponent:TDDocumentsDirectoryName isDirectory:YES];
        wrapperURL = [cloudRootURL URLByAppendingPathComponent:wrapperName];
    }
    else
    {
        wrapperURL = [FilePath getDocURL:wrapperName];
    }
    
    self.document = [[[NoteDocument alloc] initWithFileURL:wrapperURL] autorelease];
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:@"index.html" ofType:nil];
    NSString *content = [NSString stringWithContentsOfFile:path 
                                                  encoding:NSUTF8StringEncoding error:nil];
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];
    NSString *htmlName = [[[wrapperURL lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:HTMLExtentsion];
    RegularFile *htmlFile = [[RegularFile alloc] initWithFileName:htmlName data:data];
    [document addRegularFile:htmlFile];
    [htmlFile release];
    
    [document saveToURL:wrapperURL forSaveOperation:UIDocumentSaveForCreating completionHandler:^(BOOL creatSuccess) {
        
        if (creatSuccess)
        {
            Metadata * metadata = document.metadata;
            NSURL * fileURL = document.fileURL;
            UIDocumentState state = document.documentState;
            NSFileVersion * version = [NSFileVersion currentVersionOfItemAtURL:fileURL];
                        
            [document closeWithCompletionHandler:^(BOOL closeSuccess){
                
                if (closeSuccess)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{

                        DocEntity *entity = [[[DocEntity alloc] initWithFileURL:fileURL
                                                            metadata:metadata
                                                               state:state
                                                             version:version] autorelease];
                        
                        [self showDiaryContent:entity newFile:YES];
                        
                        // 数据源的添加放在消息接受中处理, 这样可以避免在push页面时看到tableView的添加动画
                        
                    });
                }
            }];
        }
    }];
}

- (void)fillCell:(AdvancedCell *)cell withEntity:(DocEntity *)entity
{
    // 这个方法不要调用tableView reloadData的方法，会造成死循环
    NSDate *date = [FilePath timeFromURL:entity.docURL];
    cell.dateText = [date mediumString];
    
    if (entity.metadata != nil)
    {
        if (entity.metadata.detailText != nil)
        {
            cell.detailText = entity.metadata.detailText;
        }
        
        if (entity.metadata.thumbnailImage != nil)
        {
            cell.thumbnail = entity.metadata.thumbnailImage;
        }
    }
}

- (void)metadataLoadSuccess:(DocEntity *)entity
{
    if (entity != nil)
    {
        entity.downloadSuccess = YES;
        AdvancedCell *cell = (AdvancedCell *)[self.mTableView cellForRowAtIndexPath:entity.indexPath];
        if (cell != nil)
        {
            [self fillCell:cell withEntity:entity];
        }
    }
}

- (void)startLoadDoc:(DocEntity *)entity forIndexPath:(NSIndexPath *)indexPath
{
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    NoteDocument *doc = [[NoteDocument alloc] initWithFileURL:entity.docURL];
    [doc openWithCompletionHandler:^(BOOL success){
        if (success)
        {
            // 只有需要去加载的时候才去设置indexPath，默认的indexPath为空
            entity.metadata = doc.metadata;
            entity.state = doc.documentState;
            entity.version = [NSFileVersion currentVersionOfItemAtURL:entity.docURL];
            entity.indexPath = indexPath;
            [doc closeWithCompletionHandler:^(BOOL closeSuccess){
                
                // Check status
                if (!closeSuccess) {
                    NSLog(@"Failed to close %@", entity.docURL);
                    // Continue anyway...
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSLog(@"metadataLoadSuccess---");
                    [self metadataLoadSuccess:entity];
                    [doc release];
                    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
                    
                });
            }];
        }
        else
        {
            NSLog(@"Failed to openWithCompletionHandler %@", entity.docURL);
        }
    }];
}

// this method is used in case the user scrolled into a set of cells that don't have their app icons yet
- (void)loadImagesForOnscreenRows
{
    if ([entityArray count] > 0)
    {
        NSArray *visiblePaths = [self.mTableView indexPathsForVisibleRows];
        for (NSIndexPath *indexPath in visiblePaths)
        {
            DocEntity *entity = [entityArray objectAtIndex:indexPath.row];
            
            if (!entity.metadata) // avoid the app icon download if the app already has an icon
            {
                [self startLoadDoc:entity forIndexPath:indexPath];
            }
        }
    }
}

- (IBAction)editAction:(id)sender
{
    [self.mTableView setEditing:YES animated:YES];
    
    NSArray *items = self.toolbar.items;
    NSArray *array = [NSArray arrayWithObjects:[items objectAtIndex:0], self.deleteButton, nil];
    [self.toolbar setItems:array animated:YES];
    
    self.navigationItem.rightBarButtonItem = self.cancelButton;
}

- (IBAction)cancelAction:(id)sender
{
    [self.mTableView setEditing:NO animated:YES];
    
    NSArray *items = self.toolbar.items;
    NSArray *array = [NSArray arrayWithObjects:[items objectAtIndex:0], self.addButton, nil];
    [self.toolbar setItems:array animated:YES];
    
    self.navigationItem.rightBarButtonItem = self.editButton;
}

- (void)deleteFileAtIndex:(NSIndexPath *)indexPath
{
    NSInteger index = [indexPath row];
    if (index < 0 || index >= [entityArray count])
    {
        return;
    }
    
    DocEntity *entity = [entityArray objectAtIndex:index];
    if (entity != nil && docAccess != nil)
    {
        [docAccess deleteFile:entity.docURL];
    }
    [entityArray removeObject:entity];
    [self.mTableView deleteRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)askIfDelete:(NSIndexPath *)indexPath
{
    self.indexPathToDel = indexPath;
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                             delegate:self
                                                    cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                               destructiveButtonTitle:NSLocalizedString(@"Delete", nil)
                                                    otherButtonTitles:nil, nil];
    actionSheet.tag = ActionSheetDelete;
    [actionSheet showFromTabBar:self.tabBarController.tabBar];
    [actionSheet release];
}

- (void)showDiaryContent:(DocEntity *)entity newFile:(BOOL)newFile
{
    NSString *htmlName = [[[entity.docURL lastPathComponent] stringByDeletingPathExtension] stringByAppendingFormat:HTMLExtentsion];
    NSURL *url = [entity.docURL URLByAppendingPathComponent:htmlName];
    DiaryContentViewController *contentViewController = [[DiaryContentViewController alloc] initWithNibName:@"DiaryContentViewController"
                                                                                                     bundle:nil];
    contentViewController.hidesBottomBarWhenPushed = YES;
    contentViewController.htmlFileURL = url;
    contentViewController.doc = document;
    contentViewController.newFile = newFile;
    contentViewController.entity = entity;
    
    [self.navigationController pushViewController:contentViewController animated:YES];
    [contentViewController release];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)share:(NSIndexPath *)indexPath
{
    self.indexPathToShare = indexPath;
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:nil
                                                             delegate:self
                                                    cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"Message", @"Email", @"Facebook", @"Twitter", nil];
    actionSheet.tag = ActionSheetShare;
    [actionSheet showFromTabBar:self.tabBarController.tabBar];
    [actionSheet release];
}

- (void)shareText:(NSString *)text index:(NSInteger)index
{
    if (index == 0)
    {
        [mySocial showSMSPicker:text];
    }
    else if (index == 1)
    {
        [mySocial showMailPicker:text];
    }
    else if (index == 2)
    {
        [mySocial showFaceBook:text];
    }
    else if (index == 3)
    {
        [mySocial showTwitter:text];
    }
//    else if (index == 4)
//    {
//        //[mySocial showSina:text];
//    }
}

#pragma mark - UIActionSheetDelegate
- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    if (actionSheet.tag == ActionSheetDelete)
    {
        if (buttonIndex == 0)
        {
            [self deleteFileAtIndex:self.indexPathToDel];
        }
    }
    else if (actionSheet.tag == ActionSheetShare)
    {
        if (indexPathToShare != nil)
        {
            DocEntity *entity = [entityArray objectAtIndex:[indexPathToShare row]];
            MFMessageComposeViewController *picker = [[MFMessageComposeViewController alloc] init];
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            pasteboard.persistent = YES;
            pasteboard.image = [UIImage imageNamed:@"title.png"];
            NSString *photoCall = @"sms:";
            NSURL *url = [NSURL URLWithString:photoCall];
            [[UIApplication sharedApplication] openURL:url];
            
            if ([MFMessageComposeViewController canSendText])
            {
                NSMutableString *enmai = [[NSMutableString alloc] initWithString:@"your email body"];
                picker.recipients = [NSArray arrayWithObjects:@"17238", nil];
                [picker setBody:enmai];
                
            }
          
            [self presentModalViewController:picker animated:YES];
           // [picker release];

            //[self shareText:detail index:buttonIndex];
        }
    }
}

#pragma mark UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    
    // @"Automatically store your documents in the cloud to keep them up-to-date across all your devices and the web."
    // Cancel: @"Later"
    // Other: @"Use iCloud"
    if (alertView.tag == 1)
    {
        if (buttonIndex == alertView.firstOtherButtonIndex) 
        {
            [docAccess setiCloudOn:YES];            
            [self reloadNotes:YES];
        }                
    } 
//    // @"What would you like to do with the documents currently on this iPad?" 
//    // Cancel: @"Continue Using iCloud" 
//    // Other 1: @"Keep a Local Copy"
//    // Other 2: @"Keep on iCloud Only"
//    else if (alertView.tag == 2) {
//        
//        if (buttonIndex == alertView.cancelButtonIndex) {
//            
//            [self setiCloudOn:YES];
//            [self refresh];
//            
//        } else if (buttonIndex == alertView.firstOtherButtonIndex) {
//            
//            if (_iCloudURLsReady) {
//                [self iCloudToLocalImpl];
//            } else {
//                _copyiCloudToLocal = YES;
//            }
//            
//        } else if (buttonIndex == alertView.firstOtherButtonIndex + 1) {            
//            
//            // Do nothing
//            
//        } 
//        
//    }
}

#pragma mark - iCloudAvailableDelegate

- (void)queryDidFinished:(NSArray *)array
{
    if (![docAccess iCloudOn])
    {
        return;
    }
    
    [entityArray removeAllObjects];
    
    for (NSMetadataItem *item in array)
    {
        NSURL *fileURL = [item valueForAttribute:NSMetadataItemURLKey];
        NSNumber *hide = nil;
  
        // Don't include hidden files
        [fileURL getResourceValue:&hide forKey:NSURLIsHiddenKey error:nil];
        if (hide && ![hide boolValue])
        {
            [self addOrUpdateEntryWithURL:fileURL metadata:nil state:UIDocumentStateNormal version:nil needReload:NO];
        }
    }
    
    // 排序
    [FilePath sortUsingDescending:entityArray];
    [self.mTableView reloadData];
}

#pragma mark - AdvanceCellDelegate

- (void)handleTouchOnCell:(AdvancedCell *)cell tag:(NSInteger)tag
{
    NSIndexPath *indexPath = [self.mTableView indexPathForCell:cell];
    if (tag == 1)
    {
        [self share:indexPath];
    }
    else if (tag == 2)
    {
        [self askIfDelete:indexPath];
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [entityArray count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    AdvancedCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil)
    {
        [self.cellNib instantiateWithOwner:self options:nil];
        cell = tmpCell;
        cell.delegate = self;
        self.tmpCell = nil;
    }
    
    NSString *backgroundImagePath = [[NSBundle mainBundle] pathForResource:@"cellBk" ofType:@"png"];
    [cell setBackgroundImageName:backgroundImagePath];
    
    if ([entityArray count] > 0)
    {
        DocEntity *entity = [entityArray objectAtIndex:[indexPath row]];
        [self fillCell:cell withEntity:entity];
        
        if (entity.metadata == nil)
        {
            // 如果为空则去加载填充
            [self startLoadDoc:entity forIndexPath:indexPath];
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    cell.backgroundColor = HEXCOLOR(0xdde7f5, 1.0);
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (!mTableView.isEditing)
    {
        DocEntity *entity = [entityArray objectAtIndex:[indexPath row]];
        if (!entity.downloadSuccess)
        {
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"notice", nil) 
                                                                message:NSLocalizedString(@"downloading", nil) 
                                                               delegate:nil
                                                      cancelButtonTitle:NSLocalizedString(@"OK", nil)
                                                      otherButtonTitles:nil, nil];
            [alertView show];
            [alertView release];
            return;
        }
        [self showDiaryContent:entity newFile:NO];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

#pragma mark -
#pragma mark Deferred image loading (UIScrollViewDelegate)

// Load images for all onscreen rows when scrolling is finished
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    if (!decelerate)
	{
        [self loadImagesForOnscreenRows];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self loadImagesForOnscreenRows];
}

@end
