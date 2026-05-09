import 'package:alist/screen/aboute_screen.dart';
import 'package:alist/screen/account_screen.dart';
import 'package:alist/screen/audio_player_screen.dart';
import 'package:alist/screen/cache_manager.dart';
import 'package:alist/screen/donate_screen.dart';
import 'package:alist/screen/download_manager_screen.dart';
import 'package:alist/screen/file_list/file_list_screen.dart';
import 'package:alist/screen/file_reader_screen.dart';
import 'package:alist/screen/file_search_screen.dart';
import 'package:alist/screen/gallery_screen.dart';
import 'package:alist/screen/home_screen.dart';
import 'package:alist/screen/iptv/iptv_player_screen.dart';
import 'package:alist/screen/iptv/iptv_screen.dart';
import 'package:alist/screen/login_screen.dart';
import 'package:alist/screen/media_kit_player_screen.dart';
import 'package:alist/screen/markdown_reader_screen.dart';
import 'package:alist/screen/office_reader_screen.dart';
import 'package:alist/screen/pdf_reader_screen.dart';
import 'package:alist/screen/player_settings_screen.dart';
import 'package:alist/screen/settings_screen.dart';
import 'package:alist/screen/splash_screen.dart';
import 'package:alist/screen/txt_reader_screen.dart';
import 'package:alist/screen/uploading_files_screen.dart';
import 'package:alist/screen/video_player_screen.dart';
import 'package:alist/screen/web_screen.dart';
import 'package:alist/util/constant.dart';
import 'package:alist/util/named_router.dart';
import 'package:flustars/flustars.dart';
import 'package:flutter/material.dart';
import 'package:get/get_navigation/src/routes/get_route.dart';

class AlistRouter {
  static const fileListRouterStackId = 1;
  static const fileListCopyMoveRouterStackId = 2;

  static Widget _audioPlayerPage() {
    final style = SpUtil.getInt(AlistConstant.audioPlayerUiStyle, defValue: 0) ?? 0;
    return style == 1 ? const AudioPlayerScreenV2() : AudioPlayerScreen();
  }

  static final List<GetPage> screens = [
    GetPage(name: NamedRouter.root, page: () => const SplashScreen()),
    GetPage(name: NamedRouter.login, page: () => LoginScreen()),
    GetPage(name: NamedRouter.home, page: () => const HomeScreen()),
    GetPage(name: NamedRouter.fileList, page: () => FileListWrapper()),
    GetPage(name: NamedRouter.settings, page: () => const SettingsScreen()),
    GetPage(
        name: NamedRouter.videoPlayer, page: () => const VideoPlayerScreen()),
    GetPage(
        name: NamedRouter.audioPlayer, page: () => _audioPlayerPage()),
    GetPage(name: NamedRouter.donate, page: () => const DonateScreen()),
    GetPage(name: NamedRouter.about, page: () => const AboutScreen()),
    GetPage(name: NamedRouter.gallery, page: () => GalleryScreen()),
    GetPage(name: NamedRouter.fileReader, page: () => FileReaderScreen()),
    GetPage(name: NamedRouter.web, page: () => const WebScreen()),
    GetPage(name: NamedRouter.pdfReader, page: () => PdfReaderScreen()),
    GetPage(name: NamedRouter.uploadingFiles, page: () => const UploadingFilesScreen()),
    GetPage(name: NamedRouter.account, page: () => const AccountScreen()),
    GetPage(name: NamedRouter.downloadManager, page: () => DownloadManagerScreen()),
    GetPage(name: NamedRouter.fileSearch, page: () => FileSearchScreen()),
    GetPage(name: NamedRouter.cacheManager, page: () => const CacheManagerScreen()),
    GetPage(name: NamedRouter.playerSettings, page: () => const PlayerSettingsScreen()),
    GetPage(name: NamedRouter.txtReader, page: () => TxtReaderScreen()),
    GetPage(name: NamedRouter.officeReader, page: () => OfficeReaderScreen()),
    GetPage(name: NamedRouter.markdownReader, page: () => MarkdownReaderScreen()),
    GetPage(name: NamedRouter.iptv, page: () => const IptvScreen()),
    GetPage(name: NamedRouter.iptvPlayer, page: () => const IptvPlayerScreen()),
    // WMV 播放器 (media_kit / libmpv)
    GetPage(name: NamedRouter.mediaKitPlayer, page: () => const MediaKitPlayerScreen()),
  ];
}
