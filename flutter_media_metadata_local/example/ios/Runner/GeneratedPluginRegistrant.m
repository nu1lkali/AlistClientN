//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<file_picker/FilePickerPlugin.h>)
#import <file_picker/FilePickerPlugin.h>
#else
@import file_picker;
#endif

#if __has_include(<flutter_media_metadata/FlutterMediaMetadataPlugin.h>)
#import <flutter_media_metadata/FlutterMediaMetadataPlugin.h>
#else
@import flutter_media_metadata;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FilePickerPlugin registerWithRegistrar:[registry registrarForPlugin:@"FilePickerPlugin"]];
  [FlutterMediaMetadataPlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterMediaMetadataPlugin"]];
}

@end
