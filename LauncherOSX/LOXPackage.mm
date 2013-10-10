//  Created by Boris Schneiderman.
//  Copyright (c) 2012-2013 The Readium Foundation.
//
//  The Readium SDK is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.


#import <ePub3/nav_element.h>
#import <ePub3/nav_table.h>
#import <ePub3/archive.h>
#import <ePub3/package.h>


#import "LOXPackage.h"
#import "LOXSpine.h"
#import "LOXSpineItem.h"
//#import "LOXTemporaryFileStorage.h"
#import "LOXUtil.h"
#import "LOXToc.h"
#import "LOXMediaOverlay.h"

#import <ePub3/utilities/byte_stream.h>

@interface LOXPackage () {
    @private std::vector<std::unique_ptr<ePub3::ByteStream>> m_archiveReaderVector;
}

- (NSString *)getLayoutProperty;

- (LOXToc *)getToc;

- (void)copyTitleFromNavElement:(ePub3::NavigationElementPtr)element toEntry:(LOXTocEntry *)entry;

//- (void)saveContentOfReader:(std::unique_ptr<ePub3::ByteStream>&)reader toPath:(NSString *)path;

@end

@implementation LOXPackage {

    ePub3::PackagePtr _sdkPackage;
    //LOXTemporaryFileStorage *_storage;

}

@synthesize packageUUID = m_packageUUID;

@synthesize spine = _spine;
@synthesize title = _title;
@synthesize packageId = _packageId;
@synthesize toc = _toc;
@synthesize rendition_layout = _rendition_layout;
//@synthesize rootDirectory = _rootDirectory;
@synthesize mediaOverlay = _mediaOverlay;


- (void)rdpackageResourceWillDeallocate:(RDPackageResource *)packageResource {
    for (auto i = m_archiveReaderVector.begin(); i != m_archiveReaderVector.end(); i++) {
        if (i->get() == packageResource.byteStream) {
            m_archiveReaderVector.erase(i);
            return;
        }
    }

    NSLog(@"The archive reader was not found!");
}

- (RDPackageResource *)resourceAtRelativePath:(NSString *)relativePath isHTML:(BOOL *)isHTML {
    if (isHTML != NULL) {
        *isHTML = NO;
    }

    if (relativePath == nil || relativePath.length == 0) {
        return nil;
    }

    NSRange range = [relativePath rangeOfString:@"#"];

    if (range.location != NSNotFound) {
        relativePath = [relativePath substringToIndex:range.location];
    }

    ePub3::string s = ePub3::string(relativePath.UTF8String);

    std::unique_ptr<ePub3::ByteStream> byteStream = _sdkPackage->ReadStreamForRelativePath(_sdkPackage->BasePath() + s);

    if (byteStream == nullptr) {
        NSLog(@"Relative path '%@' does not have an archive byte stream!", relativePath);
        return nil;
    }

    RDPackageResource *resource = [[[RDPackageResource alloc]
            initWithDelegate:self
            byteStream:byteStream.get()
                relativePath:relativePath] autorelease];

    if (resource != nil) {
        m_archiveReaderVector.push_back(std::move(byteStream));
    }

    // Determine if the data represents HTML.

    if (isHTML != NULL) {
        if ([m_relativePathsThatAreHTML containsObject:relativePath]) {
            *isHTML = YES;
        }
        else if (![m_relativePathsThatAreNotHTML containsObject:relativePath]) {
            ePub3::ManifestTable manifest = _sdkPackage->Manifest();

            for (auto i = manifest.begin(); i != manifest.end(); i++) {
                std::shared_ptr<ePub3::ManifestItem> item = i->second;

                if (item->Href() == s) {
                    if (item->MediaType() == "application/xhtml+xml") {
                        [m_relativePathsThatAreHTML addObject:relativePath];
                        *isHTML = YES;
                    }

                    break;
                }
            }

            if (*isHTML == NO) {
                [m_relativePathsThatAreNotHTML addObject:relativePath];
            }
        }
    }

    return resource;
}


- (id)initWithSdkPackage:(ePub3::PackagePtr)sdkPackage {

    self = [super init];
    if(self) {

        _sdkPackage = sdkPackage;

        if (m_packageUUID != nil)
        {
            [m_packageUUID release];
        }

        CFUUIDRef uuid = CFUUIDCreate(NULL);
        m_packageUUID = (NSString *)CFUUIDCreateString(NULL, uuid);
        CFRelease(uuid);

        m_relativePathsThatAreHTML = [[NSMutableSet alloc] init];
        m_relativePathsThatAreNotHTML = [[NSMutableSet alloc] init];

        NSString* direction;

        auto pageProgression = _sdkPackage->PageProgressionDirection();
        if(pageProgression == ePub3::PageProgression::LeftToRight) {
            direction = @"ltr";
        }
        else if(pageProgression == ePub3::PageProgression::RightToLeft) {
            direction = @"rtl";
        }
        else {
            direction = @"default";
        }

        _spine = [[LOXSpine alloc] initWithDirection:direction];
        _toc = [[self getToc] retain];
        _packageId = [[NSString stringWithUTF8String:_sdkPackage->PackageID().c_str()] retain];
        _title = [[NSString stringWithUTF8String:_sdkPackage->Title().c_str()] retain];

        _rendition_layout = [[self getLayoutProperty] retain];

//        _storage = [[self createStorageForPackage:_sdkPackage] retain];
//        _rootDirectory = [_storage.rootDirectory retain];

        auto spineItem = _sdkPackage->FirstSpineItem();
        while (spineItem) {

            //LOXSpineItem *loxSpineItem = [[[LOXSpineItem alloc] initWithStorageId:_storage.uuid forSdkSpineItem:spineItem fromPackage:self] autorelease];
            LOXSpineItem *loxSpineItem = [[[LOXSpineItem alloc] initWithSdkSpineItem:spineItem fromPackage:self] autorelease];
            [_spine addItem: loxSpineItem];
            spineItem = spineItem->Next();
        }

        _mediaOverlay = [[LOXMediaOverlay alloc] initWithSdkPackage:_sdkPackage];

        /*
        auto propList = _sdkPackage->PropertiesMatching("duration", "media");

        for(auto iter = propList.begin(); iter != propList.end(); iter++) {

            auto prop = iter;


        }
        */
    }
    
    return self;
}

-(NSString*)getLayoutProperty
{
    auto prop = _sdkPackage->PropertyMatching("layout", "rendition");
    if(prop != nullptr) {
        return [NSString stringWithUTF8String: prop->Value().c_str()];
    }

    return @"";
}

- (void)dealloc {

    [m_relativePathsThatAreHTML release];
    [m_relativePathsThatAreNotHTML release];

    [_spine release];
    [_toc release];
    //[_storage release];
    [_packageId release];
    [_title release];
    [_rendition_layout release];
    //[_rootDirectory release];
    [_mediaOverlay release];
    [super dealloc];
}

//
//- (LOXTemporaryFileStorage *)createStorageForPackage:(ePub3::PackagePtr)package
//{
//    NSString *packageBasePath = [NSString stringWithUTF8String:package->BasePath().c_str()];
//    return [[[LOXTemporaryFileStorage alloc] initWithUUID:[LOXUtil uuid] forBasePath:packageBasePath] autorelease];
//}

- (LOXToc*)getToc
{
    auto navTable = _sdkPackage->NavigationTable("toc");

    if(navTable == nil) {
        return nil;
    }

    LOXToc *toc = [[[LOXToc alloc] init] autorelease];

    toc.title = [NSString stringWithUTF8String:navTable->Title().c_str()];
    if(toc.title.length == 0) {
        toc.title = @"Table of content";
    }

    toc.sourceHref = [NSString stringWithUTF8String:navTable->SourceHref().c_str()];


    [self addNavElementChildrenFrom:std::dynamic_pointer_cast<ePub3::NavigationElement>(navTable) toTocEntry:toc];

    return toc;
}

- (void)addNavElementChildrenFrom:(ePub3::NavigationElementPtr)navElement toTocEntry:(LOXTocEntry *)parentEntry
{
    for (auto el = navElement->Children().begin(); el != navElement->Children().end(); el++) {

        ePub3::NavigationPointPtr navPoint = std::dynamic_pointer_cast<ePub3::NavigationPoint>(*el);

        if(navPoint != nil) {

            LOXTocEntry *entry = [[[LOXTocEntry alloc] init] autorelease];
            [self copyTitleFromNavElement:navPoint toEntry:entry];
            entry.contentRef = [NSString stringWithUTF8String:navPoint->Content().c_str()];

            [parentEntry addChild:entry];

            [self addNavElementChildrenFrom:navPoint toTocEntry:entry];
        }

    }
}

-(void)copyTitleFromNavElement:(ePub3::NavigationElementPtr)element toEntry:(LOXTocEntry *)entry
{
    NSString *title = [NSString stringWithUTF8String: element->Title().c_str()];
    entry.title = [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

}
//
//-(void)prepareResourceWithPath:(NSString *)path
//{
//
//    if (![_storage isLocalResourcePath:path]) {
//        return;
//    }
//
//    if([_storage isResoursFoundAtPath:path]) {
//        return;
//    }
//
//    NSString * relativePath = [_storage relativePathFromFullPath:path];
//
//    std::string str([relativePath UTF8String]);
//
//    // DEPRECATED (use ByteStream instead)
//    //ePub3::unique_ptr<ePub3::ArchiveReader>& reader = _sdkPackage->ReaderForRelativePath(str);
//
//    std::unique_ptr<ePub3::ByteStream> reader = _sdkPackage->ReadStreamForRelativePath(_sdkPackage->BasePath() + str);
//
//    if(reader == NULL){
//        NSLog(@"No archive found for path %@", relativePath);
//        return;
//    }
//
//    [self saveContentOfReader:reader toPath: path];
//}
//
//- (void)saveContentOfReader: (std::unique_ptr<ePub3::ByteStream> &) reader toPath:(NSString *)path
//{
//    uint8_t buffer[1024];
//
//    NSMutableData * data = [NSMutableData data];
//
//    ssize_t readBytes = 0;
//    while ((readBytes  = reader->ReadBytes(buffer, 1024)) > 0) {
//        [data appendBytes:buffer length:(NSUInteger) readBytes];
//    }
//
//    [_storage saveData:data  toPaht:path];
//}

-(NSString*) getCfiForSpineItem:(LOXSpineItem *) spineItem
{
    ePub3::string cfi = _sdkPackage->CFIForSpineItem([spineItem sdkSpineItem]).String();
    NSString * nsCfi = [NSString stringWithUTF8String: cfi.c_str()];
    return [self unwrapCfi: nsCfi];
}

-(NSString *)unwrapCfi:(NSString *)cfi
{
    if ([cfi hasPrefix:@"epubcfi("] && [cfi hasSuffix:@")"]) {
        NSRange r = NSMakeRange(8, [cfi length] - 9);
        return [cfi substringWithRange:r];
    }

    return cfi;
}

-(NSDictionary *) toDictionary
{
    NSMutableDictionary * dict = [NSMutableDictionary dictionary];

    //[dict setObject:_rootDirectory forKey:@"rootUrl"];
    [dict setObject:@"/" forKey:@"rootUrl"];

    [dict setObject:_rendition_layout forKey:@"rendition_layout"];
    [dict setObject:[_spine toDictionary] forKey:@"spine"];
    [dict setObject:[_mediaOverlay toDictionary] forKey:@"media_overlay"];


    return dict;
}

-(ePub3::PackagePtr) sdkPackage
{
    return _sdkPackage;
}

//-(LOXTemporaryFileStorage *) storage
//{
//    return _storage;
//}

@end