import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/firebase_config.dart';
import '../screens/notifications_screen.dart';
import 'app_navigation.dart';
import 'local_storage_service.dart';
import 'notification_service.dart';
import 'supabase_backend_service.dart';

@pragma('vm:entry-point')
Future<void> huimBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();

  final recipientId = message.data['recipientId']?.toString().trim() ?? '';
  if (recipientId.isEmpty) return;

  final enabled = await LocalStorageService.loadPushEnabled();
  if (!enabled) return;

  final activeUserId = await LocalStorageService.loadPushActiveUserId();
  if (activeUserId == null || activeUserId != recipientId) return;

  final title = message.data['title']?.toString() ?? 'GardeFlow';
  final body =
      message.data['body']?.toString() ?? 'Nouvelle notification';
  final kind = message.data['kind']?.toString() ?? '';

  await NotificationService.instance.init();
  await NotificationService.instance.showPush(
    title: title,
    body: body,
    kind: kind,
  );
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final status = ValueNotifier<String>('Notifications non activées');
  bool _initialized = false;
  bool _enabled = false;
  bool _navigationReady = false;
  bool _isAdmin = false;
  String? _pendingKind;
  String? _registeredToken;
  StreamSubscription<String>? _tokenRefreshSub;
  Future<void> _operations = Future<void>.value();

  bool get initialized => _initialized;
  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get _nativePush => _android || _ios;
  String get _platform => kIsWeb ? 'web' : _ios ? 'ios' : 'android';

  bool _belongsToCurrentUser(RemoteMessage message) {
    final recipientId = message.data['recipientId']?.toString();
    if (recipientId == null || recipientId.isEmpty) return false;
    return SupabaseBackendService.instance.client.auth.currentUser?.id == recipientId;
  }

  Future<void> initializeFirebase() async {
    if (_initialized || (!kIsWeb && !_nativePush)) return;
    try {
      await Firebase.initializeApp(options: kIsWeb ? HuimFirebaseConfig.webOptions : null);
      if (_nativePush) {
        FirebaseMessaging.onBackgroundMessage(huimBackgroundMessage);
        NotificationService.instance.onPushTap = _open;
        final pending = NotificationService.instance.pendingPushKind;
        if (pending != null) _pendingKind = pending;
      }
      if (_ios) {
        await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
          alert: false,
          badge: false,
          sound: false,
        );
      }
      FirebaseMessaging.onMessage.listen((message) async {
        if (!_enabled || !_belongsToCurrentUser(message)) return;
        final title = message.data['title']?.toString() ?? message.notification?.title ?? 'GardeFlow';
        final body = message.data['body']?.toString() ?? message.notification?.body ?? 'Nouvelle notification';
        final kind = message.data['kind']?.toString() ?? '';
        try {
          if (_nativePush) {
            await NotificationService.instance.showPush(title: title, body: body, kind: kind);
          } else {
            huimMessengerKey.currentState?.showSnackBar(SnackBar(
              content: Text('$title — $body'),
              action: SnackBarAction(label: 'Voir', onPressed: () => _open(kind)),
            ));
          }
        } catch (e) {
          status.value = 'Impossible d’afficher la notification';
          debugPrint('Affichage push impossible: $e');
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (_belongsToCurrentUser(message)) {
          _open(message.data['kind']?.toString() ?? '');
        }
      });
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null && _belongsToCurrentUser(initial)) {
        _pendingKind = initial.data['kind']?.toString() ?? '';
      }
      _initialized = true;
      status.value = 'Notifications prêtes à être activées';
    } catch (e) {
      status.value = 'Firebase indisponible : vérifier la configuration Firebase de cet appareil';
      debugPrint('Initialisation Firebase impossible: $e');
    }
  }

  // Appelé uniquement après l'arrivée sur l'accueil : le splash et la connexion
  // doivent terminer avant d'ouvrir une page à partir d'une notification.
  void navigationReady({required bool isAdmin}) {
    _navigationReady = true;
    _isAdmin = isAdmin;
    final kind = _pendingKind;
    _pendingKind = null;
    if (kind != null) _open(kind);
  }

  void _open(String kind) {
    if (!_navigationReady || huimNavigatorKey.currentState == null) {
      _pendingKind = kind;
      return;
    }
    final isAccountNotification =
        kind == 'account_created' || kind == 'password_reset_request';
    final initialIndex = kind.startsWith('exchange_')
        ? 1
        : kind.startsWith('leave_')
            ? 2
            : (isAccountNotification && _isAdmin ? 3 : 0);
    huimNavigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(initialIndex: initialIndex),
      ),
    );
  }

  Future<String?> _getToken() async {
    if (_ios) {
      // Sur iPhone, FCM a besoin du token APNs. Il peut arriver quelques
      // instants après l'autorisation système, surtout au premier lancement.
      for (var i = 0; i < 12; i++) {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns != null && apns.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }
    }
    return FirebaseMessaging.instance.getToken(
      vapidKey: kIsWeb ? HuimFirebaseConfig.webVapidKey : null,
    );
  }

  // Sérialiser activation, rafraîchissement et désactivation évite qu'un token
  // soit réinscrit après une déconnexion ou un changement rapide de réglage.
  Future<void> _enqueue(Future<void> Function() operation) {
    _operations = _operations.then((_) => operation()).catchError((Object e) {
      status.value = 'Activation impossible. Vérifier Internet puis réessayer.';
      debugPrint('Opération push impossible: $e');
    });
    return _operations;
  }

  Future<void> activateForSignedInUser() {
    _enabled = true;
    return _enqueue(() async {
      if (!_enabled) return;
      if (!_initialized) await initializeFirebase();
      final backend = SupabaseBackendService.instance;
      if (!_initialized || !backend.enabled) return;
      final userId = backend.client.auth.currentUser?.id;
      if (userId == null) return;
      final deviceId = await LocalStorageService.loadOrCreatePushDeviceId();
      await LocalStorageService.savePushActiveUserId(userId);
      final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        await LocalStorageService.savePushEnabled(false);
        status.value = 'Autorisation refusée : activer les notifications dans les réglages du téléphone';
        return;
      }
      final token = await _getToken();
      if (!_enabled || backend.client.auth.currentUser?.id != userId) return;
      if (token == null || token.isEmpty) {
        status.value = _ios
            ? 'Aucun token reçu. Vérifier Internet, APNs et la configuration Firebase iOS.'
            : 'Aucun token reçu. Vérifier Internet et Google Play Services.';
        return;
      }
      await backend.registerPushDevice(token, platform: _platform, deviceId: deviceId);
      await LocalStorageService.savePushEnabled(true);
      _registeredToken = token;
      status.value = 'Notifications push activées sur cet appareil';
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        unawaited(_enqueue(() async {
          if (!_enabled || backend.client.auth.currentUser?.id != userId) return;
          final previousToken = _registeredToken;
          await backend.registerPushDevice(token, platform: _platform, deviceId: deviceId);
          if (previousToken != null && previousToken.isNotEmpty && previousToken != token) {
            try {
              await backend.unregisterPushToken(previousToken);
            } catch (e) {
              debugPrint('Ancien token push non supprimé immédiatement: $e');
            }
          }
          _registeredToken = token;
          status.value = 'Notifications push activées sur cet appareil';
        }));
      }, onError: (Object e) {
        status.value = 'Renouvellement des notifications impossible. Réessayer.';
      });
    });
  }

  Future<void> unregisterCurrentDevice() {
    _enabled = false;
    unawaited(LocalStorageService.savePushEnabled(false));
    _navigationReady = false;
    _pendingKind = null;
    return _enqueue(() async {
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      if (!_initialized) return;
      try {
        final token = _registeredToken ?? await _getToken();
        final backend = SupabaseBackendService.instance;
        if (token != null && backend.enabled && backend.client.auth.currentUser != null) {
          await backend.unregisterPushToken(token);
        }
      } finally {
        // Invalider aussi chez FCM, même si la suppression Supabase échoue.
        await FirebaseMessaging.instance.deleteToken();
        _registeredToken = null;
        status.value = 'Notifications push désactivées sur cet appareil';
      }
    });
  }
}
