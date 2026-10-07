import 'package:flutter/material.dart';
import 'package:localsend_app/pages/pairing/pairing_cards.dart';

Future<void> showReceivePairingDialog(BuildContext context, {bool allowWebDropLinks = false}) async {
  await showPairingReceiveCard(context, allowWebDropLinks: allowWebDropLinks);
}
