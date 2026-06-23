import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

class OfflineBanner extends StatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});
  @override State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r)=>r==ConnectivityResult.none);
      if(mounted) setState(()=>_offline=offline);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children:[
      AnimatedCrossFade(
        firstChild: Container(
          width: double.infinity, color: AppColors.amber, padding: const EdgeInsets.symmetric(vertical:8),
          child: const Row(mainAxisAlignment:MainAxisAlignment.center, children:[
            Icon(Icons.wifi_off, size:16, color:Colors.white),
            SizedBox(width:8),
            Text('No internet — showing cached data', style:TextStyle(color:Colors.white,fontSize:12)),
          ]),
        ),
        secondChild: const SizedBox.shrink(),
        crossFadeState: _offline ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        duration: const Duration(milliseconds:300),
      ),
      Expanded(child: widget.child),
    ]);
  }
}
