import 'package:flutter/foundation.dart';

enum TransitConnectionState { online, cached, offline }

class DebugConfig {
  static final ValueNotifier<String> transitStatus = ValueNotifier<String>('Iniciando...');
  static final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
  static final ValueNotifier<String?> detailedError = ValueNotifier<String?>(null);
  
  // Dynamic signal strength connection state
  static final ValueNotifier<TransitConnectionState> connectionState = 
      ValueNotifier<TransitConnectionState>(TransitConnectionState.offline);
      
  static final ValueNotifier<DateTime?> cacheTimestamp = ValueNotifier<DateTime?>(null);
  
  static void updateStatus(String status, {bool loading = false}) {
    transitStatus.value = status;
    isLoading.value = loading;
  }
}
