import 'package:alist/util/widget_utils.dart';
import 'package:flutter/material.dart';

class AlistScaffold extends StatelessWidget {
  const AlistScaffold({
    Key? key,
    this.appbarTitle,
    required this.body,
    this.onLeadingDoubleTap,
    this.resizeToAvoidBottomInset,
    this.appbarActions,
    this.showAppbar = true,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  }) : super(key: key);
  final Widget? appbarTitle;
  final Widget body;
  final GestureTapCallback? onLeadingDoubleTap;
  final bool? resizeToAvoidBottomInset;
  final List<Widget>? appbarActions;
  final bool showAppbar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    bool isDarkMode = WidgetUtils.isDarkMode(context);
    final ModalRoute<dynamic>? parentRoute = ModalRoute.of(context);
    var canPop = null != parentRoute && parentRoute.canPop;

    return Scaffold(
      backgroundColor: null,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset ?? true,
      appBar: !showAppbar
          ? null
          : AppBar(
              leading: canPop
                  ? GestureDetector(
                      onDoubleTap: onLeadingDoubleTap,
                      child: const BackButton(),
                    )
                  : null,
              automaticallyImplyLeading: false,
              backgroundColor: null,
              toolbarHeight: kToolbarHeight + 8,
              title: appbarTitle,
              titleSpacing: canPop ? null : NavigationToolbar.kMiddleSpacing,
              actions: appbarActions,
            ),
      body: SafeArea(child: body),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }
}
