import 'package:flutter/foundation.dart';

final transferProgressPageVisibility = ValueNotifier<int>(0);

void showTransferProgressPage() {
  transferProgressPageVisibility.value++;
}

void hideTransferProgressPage() {
  if (transferProgressPageVisibility.value > 0) {
    transferProgressPageVisibility.value--;
  }
}
