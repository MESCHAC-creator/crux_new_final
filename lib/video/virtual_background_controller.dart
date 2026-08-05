import 'dart:io';

/// Modes de fond virtuel CRUX.
sealed class VirtualBackgroundMode {
  const VirtualBackgroundMode();
}

class VirtualBackgroundNone extends VirtualBackgroundMode {
  const VirtualBackgroundNone();
}

sealed class VirtualBackgroundBlur extends VirtualBackgroundMode {
  const VirtualBackgroundBlur();
}

class VirtualBackgroundBlurLight extends VirtualBackgroundBlur {
  const VirtualBackgroundBlurLight();
}

class VirtualBackgroundBlurStrong extends VirtualBackgroundBlur {
  const VirtualBackgroundBlurStrong();
}

class VirtualBackgroundImage extends VirtualBackgroundMode {
  final File image;
  const VirtualBackgroundImage(this.image);
}
