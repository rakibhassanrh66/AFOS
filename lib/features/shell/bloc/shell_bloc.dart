import 'package:flutter_bloc/flutter_bloc.dart';

abstract class ShellEvent {}
class OpenMenu    extends ShellEvent {}
class CloseMenu   extends ShellEvent {}
class ToggleMenu  extends ShellEvent {}

// `SelectItem(index)` and `ShellState.selectedIndex` used to live here. The
// index was written only by a slide-menu tap and read only by the slide-menu
// highlight, so reaching a screen any other way (dashboard tile, search result,
// notification) left the menu highlighting a screen the user was no longer on.
// Highlighting is derived from the actual route now (see
// core/navigation/router_location.dart), which leaves nothing for the index to
// do -- keeping it would only invite something to start trusting it again. The
// tap site dispatches CloseMenu, which is the part that was actually load-bearing.
class ShellState {
  final bool isOpen;
  const ShellState({this.isOpen=false});
  ShellState copyWith({bool? isOpen}) => ShellState(isOpen:isOpen??this.isOpen);
}

class ShellBloc extends Bloc<ShellEvent,ShellState> {
  ShellBloc():super(const ShellState()){
    on<OpenMenu>((e,emit)=>emit(state.copyWith(isOpen:true)));
    on<CloseMenu>((e,emit)=>emit(state.copyWith(isOpen:false)));
    on<ToggleMenu>((e,emit)=>emit(state.copyWith(isOpen:!state.isOpen)));
  }
}
