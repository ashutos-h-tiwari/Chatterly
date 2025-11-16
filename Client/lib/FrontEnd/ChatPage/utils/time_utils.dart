import 'package:flutter/material.dart';

String formatTimestampLocal(DateTime ts) {
  final local = ts.toLocal();
  final now = DateTime.now();
  if (now.difference(local).inDays == 0) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return "$hh:$mm";
  }
  return "${local.day}/${local.month}/${local.year}";
}

/// If the server timestamp is basically the same as the local pending one,
/// keep the local (prevents the “jump” after send due to timezone offsets).
DateTime resolveSendTimestamp(DateTime serverLocal, DateTime pendingLocal,
    {int toleranceSeconds = 90}) {
  final delta = serverLocal.difference(pendingLocal).inSeconds.abs();
  return delta <= toleranceSeconds ? pendingLocal : serverLocal;
}
