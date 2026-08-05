import 'package:flutter/material.dart';
import 'virtual_background_mode.dart';

/// Contrôleur du fond virtuel CRUX.
class VirtualBackgroundController extends ChangeNotifier {
  VirtualBackgroundMode _mode = const VirtualBackgroundNone();

  VirtualBackgroundMode get mode => _mode;

  void setMode(VirtualBackgroundMode mode) {
    _mode = mode;
    notifyListeners();
  }
}
