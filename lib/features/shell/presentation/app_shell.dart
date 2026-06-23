import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/shell_bloc.dart';
import 'slide_menu.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:(_)=>ShellBloc(),
      child: Builder(builder:(ctx)=>_ShellBody(child:child)),
    );
  }
}

class _ShellBody extends StatelessWidget {
  final Widget child;
  const _ShellBody({required this.child});
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShellBloc,ShellState>(
      builder:(ctx,state) => Scaffold(
        backgroundColor: const Color(0xFF060D1F),
        body: Stack(children:[
          child,
          // Blur overlay
          if(state.isOpen)
            GestureDetector(
              onTap:()=>ctx.read<ShellBloc>().add(CloseMenu()),
              child: Container(
                color: Colors.black.withOpacity(0.6),
              ),
            ),
          // Slide menu
          AnimatedPositioned(
            duration: const Duration(milliseconds:300),
            curve: Curves.easeOutCubic,
            left: state.isOpen ? 0 : -320,
            top:0, bottom:0, width:300,
            child: const SlideMenu(),
          ),
        ]),
      ),
    );
  }
}
