import 'package:flutter_bloc/flutter_bloc.dart';

abstract class ShellEvent {}
class OpenMenu    extends ShellEvent {}
class CloseMenu   extends ShellEvent {}
class ToggleMenu  extends ShellEvent {}
class SelectItem  extends ShellEvent { final int index; SelectItem(this.index); }

class ShellState {
  final bool isOpen;
  final int selectedIndex;
  const ShellState({this.isOpen=false, this.selectedIndex=0});
  ShellState copyWith({bool? isOpen, int? selectedIndex}) =>
    ShellState(isOpen:isOpen??this.isOpen, selectedIndex:selectedIndex??this.selectedIndex);
}

class ShellBloc extends Bloc<ShellEvent,ShellState> {
  ShellBloc():super(const ShellState()){
    on<OpenMenu>((e,emit)=>emit(state.copyWith(isOpen:true)));
    on<CloseMenu>((e,emit)=>emit(state.copyWith(isOpen:false)));
    on<ToggleMenu>((e,emit)=>emit(state.copyWith(isOpen:!state.isOpen)));
    on<SelectItem>((e,emit)=>emit(state.copyWith(selectedIndex:e.index,isOpen:false)));
  }
}
