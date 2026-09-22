import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:huim6_planning/config/backend_config.dart';
import 'package:huim6_planning/data/hospitals.dart';
import 'package:huim6_planning/models/app_user.dart';
import 'package:huim6_planning/models/exchange_request.dart';
import 'package:huim6_planning/models/planning_entry.dart';
import 'package:huim6_planning/models/planning_month.dart';
import 'package:huim6_planning/screens/home_screen.dart';
import 'package:huim6_planning/screens/more_screen.dart';
import 'package:huim6_planning/screens/shift_details_sheet.dart';
import 'package:huim6_planning/screens/settings_screen.dart';
import 'package:huim6_planning/screens/auth_screen.dart';
import 'package:huim6_planning/state/app_state.dart';
import 'package:huim6_planning/theme/app_theme.dart';
import 'package:huim6_planning/ui/planning_access.dart';
import 'package:huim6_planning/widgets/planning_calendar.dart';

AppUser doctor({bool admin = false}) => AppUser(id: 'ui-doctor', nom: 'Exemple', prenom: 'Amine', phone: '+212600000001',
  passwordHash: '', passwordSalt: '', service: 'Imagerie Médicale', grade: MedicalGrade.junior,
  hospital: kHospitalBouskoura, role: admin ? UserRole.admin : UserRole.medecin);

Future<AppState> fixture({bool admin = false, bool locked = false, bool disciplinary = false}) async {
  final user = doctor(admin: admin), now = DateTime.now();
  final date = DateTime(now.year, now.month + 1, 15);
  SharedPreferences.setMockInitialValues({'huim6_state_v5': jsonEncode({
    'users': [user.toJson()], 'notificationsOn': false,
    'planning': [PlanningEntry(id: 'ui-shift', dateStr: AppState.dateKey(date), shiftId: 'urg-nuit',
      ownerId: user.id, ownerPhone: user.phone, ownerName: user.fullName, isDisciplinary: disciplinary).toJson()],
    'planningMonths': [PlanningMonth(ownerId: user.id, year: date.year, month: date.month,
      status: locked ? PlanningMonthStatus.approved : PlanningMonthStatus.draft).toJson()],
  })});
  final state = await AppState.load();
  state.currentUser = user;
  addTearDown(state.dispose);
  return state;
}

Future<AppState> workflowFixture({required String sourceShift, String? targetShift}) async {
  final sender = doctor();
  final recipient = AppUser(id: 'recipient', nom: 'Test', prenom: 'Sara', phone: '+212600000002',
    passwordHash: '', passwordSalt: '', service: sender.service, grade: MedicalGrade.senior,
    hospital: sender.hospital, role: UserRole.medecin);
  final now = DateTime.now();
  final date = DateTime(now.year, now.month + 1, 15);
  final people = [sender, recipient];
  SharedPreferences.setMockInitialValues({'huim6_state_v5': jsonEncode({
    'users': people.map((u) => u.toJson()).toList(), 'notificationsOn': false,
    'planning': [
      PlanningEntry(id: 'source', dateStr: AppState.dateKey(date), shiftId: sourceShift,
        ownerId: sender.id, ownerPhone: sender.phone, ownerName: sender.fullName).toJson(),
      if (targetShift != null) PlanningEntry(id: 'target', dateStr: AppState.dateKey(date), shiftId: targetShift,
        ownerId: recipient.id, ownerPhone: recipient.phone, ownerName: recipient.fullName).toJson(),
    ],
    'planningMonths': people.map((u) => PlanningMonth(ownerId: u.id, year: date.year, month: date.month,
      status: PlanningMonthStatus.approved).toJson()).toList(),
  })});
  final state = await AppState.load();
  state.currentUser = sender;
  await state.setNotificationsOn(false);
  addTearDown(state.dispose);
  return state;
}
Widget host(AppState state, Widget child, {String theme = 'green', double scale = 1}) {
  AppColors.setAppearanceTheme(theme);
  return ChangeNotifierProvider.value(value: state, child: MaterialApp(
    theme: AppTheme.forAppearance(theme), locale: const Locale('fr', 'FR'),
    localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    supportedLocales: const [Locale('fr', 'FR')],
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: RepaintBoundary(key: const ValueKey('preview'), child: child),
  ));
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await initializeDateFormatting('fr_FR');
    await Supabase.initialize(
      url: BackendConfig.supabaseUrl,
      anonKey: BackendConfig.supabasePublishableKey,
    );
  });
  for (final scale in [1.0, 1.4, 2.0]) {
    testWidgets('entire month at 320 px / text $scale with discipline mark', (tester) async {
      tester.view.physicalSize = const Size(320, 1000); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final state = await fixture(disciplinary: true);
      final entry = state.planning.first, date = DateTime.parse(state.planning.first.dateStr);
      DateTime? selected;
      await tester.pumpWidget(host(state, Scaffold(body: SingleChildScrollView(child: PlanningCalendar(
        month: date, entries: {entry.dateStr: entry}, onDayTap: (d) => selected = d))), scale: scale));
      await tester.pump();
      expect(find.text('15'), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('calendar-day-${entry.dateStr}')));
      expect(selected?.day, 15);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final locked in [false, true]) {
    testWidgets('disciplinary shift stays protected before/after validation ($locked)', (tester) async {
      final state = await fixture(locked: locked, disciplinary: true);
      final entry = state.planning.first, date = DateTime.parse(state.planning.first.dateStr);
      expect(planningEditReason(state, date, entry), contains('disciplinaire'));
      expect(exchangeDisabledReason(state, entry), contains('disciplinaire'));
      await tester.pumpWidget(host(state, Scaffold(body: ShiftDetailsSheet(date: date))));
      await tester.pump();
      final exchange = tester.widget<FilledButton>(find.byType(FilledButton).first);
      expect(exchange.onPressed, isNull);
      expect(find.text('Retirer cette garde'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  test('past month is read only and admin retains disciplinary removal permission', () async {
    final state = await fixture(admin: true, disciplinary: true);
    final now = DateTime.now();
    expect(state.canEditMyPlanningMonth(DateTime(now.year, now.month - 1)), isFalse);
    expect(state.canAdminDeleteEntry(state.planning.first), isTrue);
    state.currentUser = doctor();
    expect(state.canAdminDeleteEntry(state.planning.first), isFalse);
  });
  for (final serviceOnly in [true, false]) {
    test('same-day day/night exchange preserves approval workflow (service=$serviceOnly)', () async {
      final state = await workflowFixture(sourceShift: serviceOnly ? 'service-nuit' : 'urg-nuit',
        targetShift: serviceOnly ? 'service-jour' : 'urg-jour');
      final source = state.planning.firstWhere((e) => e.id == 'source');
      final target = state.planning.firstWhere((e) => e.id == 'target');
      final recipient = state.exchangeTargets(sameServiceOnly: serviceOnly).firstWhere((d) => d.id == 'recipient');
      expect(swapTargetDisabledReason(state, source, recipient, target), isNull);
      expect(await state.createSwapRequest(source.dateStr, source, recipient, target), isNull);
      state.currentUser = state.users.firstWhere((u) => u.id == recipient.id);
      expect(await state.acceptExchange(state.exchanges.single.id), isNull);
      expect(state.exchanges.single.status, serviceOnly ? ExchangeStatus.approved : ExchangeStatus.pendingAdmin);
      expect(state.canAdminDeleteEntry(source), isFalse, reason: 'Senior does not grant administrative rights.');
      expect(source.shiftId, serviceOnly ? 'service-jour' : 'urg-nuit');
    });
  }
  test('transfer still requires recipient acceptance then administrator validation', () async {
    final state = await workflowFixture(sourceShift: 'urg-nuit');
    final source = state.planning.single;
    final recipient = state.exchangeTargets().firstWhere((d) => d.id == 'recipient');
    expect(transferTargetDisabledReason(state, source, recipient), isNull);
    expect(await state.createTransferRequest(source.dateStr, source, recipient), isNull);
    expect(state.exchanges.single.status, ExchangeStatus.pendingB);
    state.currentUser = state.users.firstWhere((u) => u.id == recipient.id);
    expect(await state.acceptExchange(state.exchanges.single.id), isNull);
    expect(state.exchanges.single.status, ExchangeStatus.pendingAdmin);
    expect(source.ownerId, 'ui-doctor');
  });
  for (final theme in ['green', 'red', 'white', 'black']) {
    testWidgets('$theme dashboard small smartphone and preview', (tester) async {
      tester.view.physicalSize = const Size(390, 844); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final state = await fixture();
      await tester.pumpWidget(host(state, const HomeScreen(), theme: theme));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Pas de garde\naujourd’hui'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('preview')));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('test/previews').createSync(recursive: true);
        File('test/previews/home-$theme.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('appearance, admin sections and login with enlarged text and keyboard', (tester) async {
    tester.view.physicalSize = const Size(320, 568); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio); addTearDown(tester.view.resetViewInsets);
    final state = await fixture(admin: true);
    for (final screen in [const ApplicationSettingsScreen(), const AdminHubScreen(), const AuthScreen()]) {
      await tester.pumpWidget(host(state, screen, scale: 1.6));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    }
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
