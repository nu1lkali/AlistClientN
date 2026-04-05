import 'package:alist/generated/images.dart';
import 'package:alist/widget/alist_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alist/l10n/intl_keys.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlistScaffold(
      appbarTitle: Text(Intl.screenName_about.tr),
      body: const _AboutPageContainer(),
    );
  }
}

class _AboutPageContainer extends StatefulWidget {
  const _AboutPageContainer({Key? key}) : super(key: key);

  @override
  State<_AboutPageContainer> createState() => _AboutPageContainerState();
}

class _AboutPageContainerState extends State<_AboutPageContainer> {
  PackageInfo? packageInfo;

  @override
  void initState() {
    super.initState();
    initPackageInfo();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Image.asset(Images.logo),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              Intl.appName.tr,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text("v${packageInfo?.version ?? ""}"),
          ),
          const SizedBox(height: 30),
          _buildProjectLink(
            context,
            '本项目',
            'https://github.com/nu1lkali/AlistClientN',
          ),
          const SizedBox(height: 12),
          _buildProjectLink(
            context,
            '原项目 (感谢 BFWXKJGS)',
            'https://github.com/BFWXKJGS/AlistClient',
          ),
        ],
      ),
    );
  }

  Widget _buildProjectLink(BuildContext context, String label, String url) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    url,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  initPackageInfo() async {
    packageInfo = await PackageInfo.fromPlatform();
    setState(() {});
  }
}
