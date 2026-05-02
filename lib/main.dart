import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

final DateFormat compactDate = DateFormat('dd MMM yyyy');
final DateFormat fileDate = DateFormat('yyyyMMdd_HHmmss');

const List<String> policyTypes = <String>[
  'Comprehensive',
  'Package',
  'Third Party',
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = PolicyRepository();
  await repository.init();
  final notifications = RenewalNotificationService();
  await notifications.init();
  runApp(AdvisorApp(repository: repository, notifications: notifications));
}

enum PolicyStatus { active, expiringSoon, expired }

class PolicyRecord {
  PolicyRecord({
    this.id,
    required this.srNo,
    required this.vehicleNumber,
    required this.customerName,
    required this.contactNumber,
    required this.registrationDate,
    required this.makeModel,
    required this.insuranceCompany,
    required this.policyNumber,
    required this.policyStartDate,
    required this.policyEndDate,
    required this.policyType,
    required this.premiumAmount,
    required this.referenceContact,
    required this.piDone,
    required this.agentName,
    required this.rcDocument,
    required this.policyDocument,
    required this.kycDocument,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int srNo;
  final String vehicleNumber;
  final String customerName;
  final String contactNumber;
  final DateTime registrationDate;
  final String makeModel;
  final String insuranceCompany;
  final String policyNumber;
  final DateTime policyStartDate;
  final DateTime policyEndDate;
  final String policyType;
  final double premiumAmount;
  final String referenceContact;
  final bool piDone;
  final String agentName;
  final String rcDocument;
  final String policyDocument;
  final String kycDocument;
  final DateTime createdAt;
  final DateTime updatedAt;

  DateTime get renewalReminder => policyEndDate.subtract(const Duration(days: 15));

  int get daysUntilExpiry {
    final today = DateUtils.dateOnly(DateTime.now());
    final end = DateUtils.dateOnly(policyEndDate);
    return end.difference(today).inDays;
  }

  PolicyStatus get status {
    final days = daysUntilExpiry;
    if (days < 0) {
      return PolicyStatus.expired;
    }
    if (days <= 15) {
      return PolicyStatus.expiringSoon;
    }
    return PolicyStatus.active;
  }

  bool get isActive => status != PolicyStatus.expired;

  String get statusLabel {
    switch (status) {
      case PolicyStatus.active:
        return 'Active';
      case PolicyStatus.expiringSoon:
        return 'Expiring soon';
      case PolicyStatus.expired:
        return 'Expired';
    }
  }

  Color statusColor(BuildContext context) {
    switch (status) {
      case PolicyStatus.active:
        return Colors.green.shade700;
      case PolicyStatus.expiringSoon:
        return Colors.red.shade700;
      case PolicyStatus.expired:
        return Theme.of(context).colorScheme.outline;
    }
  }

  String get reminderMessage {
    return 'Dear $customerName, your vehicle insurance for $vehicleNumber '
        'expires on ${compactDate.format(policyEndDate)}. Please contact '
        '$agentName for renewal.';
  }

  Map<String, Object?> toDbMap({bool includeId = false}) {
    return <String, Object?>{
      if (includeId) 'id': id,
      'srNo': srNo,
      'vehicleNumber': vehicleNumber,
      'customerName': customerName,
      'contactNumber': contactNumber,
      'registrationDate': registrationDate.toIso8601String(),
      'makeModel': makeModel,
      'insuranceCompany': insuranceCompany,
      'policyNumber': policyNumber,
      'policyStartDate': policyStartDate.toIso8601String(),
      'policyEndDate': policyEndDate.toIso8601String(),
      'policyType': policyType,
      'premiumAmount': premiumAmount,
      'renewalReminder': renewalReminder.toIso8601String(),
      'referenceContact': referenceContact,
      'piDone': piDone ? 1 : 0,
      'agentName': agentName,
      'rcDocument': rcDocument,
      'policyDocument': policyDocument,
      'kycDocument': kycDocument,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory PolicyRecord.fromMap(Map<String, Object?> map) {
    return PolicyRecord(
      id: _asIntOrNull(map['id']),
      srNo: _asInt(map['srNo']),
      vehicleNumber: _asString(map['vehicleNumber']),
      customerName: _asString(map['customerName']),
      contactNumber: _asString(map['contactNumber']),
      registrationDate: _asDate(map['registrationDate']),
      makeModel: _asString(map['makeModel']),
      insuranceCompany: _asString(map['insuranceCompany']),
      policyNumber: _asString(map['policyNumber']),
      policyStartDate: _asDate(map['policyStartDate']),
      policyEndDate: _asDate(map['policyEndDate']),
      policyType: _asString(map['policyType'], fallback: policyTypes.first),
      premiumAmount: _asDouble(map['premiumAmount']),
      referenceContact: _asString(map['referenceContact']),
      piDone: _asInt(map['piDone']) == 1,
      agentName: _asString(map['agentName']),
      rcDocument: _asString(map['rcDocument']),
      policyDocument: _asString(map['policyDocument']),
      kycDocument: _asString(map['kycDocument']),
      createdAt: _asDate(map['createdAt']),
      updatedAt: _asDate(map['updatedAt']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse('$value') ?? 0;
  }

  static int? _asIntOrNull(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse('$value');
  }

  static double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse('$value') ?? 0;
  }

  static String _asString(Object? value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }
    final text = '$value'.trim();
    return text.isEmpty ? fallback : text;
  }

  static DateTime _asDate(Object? value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    return parsed ?? DateTime.now();
  }
}

class PolicyRepository {
  static const String _table = 'policies';
  Database? _db;

  Future<void> init() async {
    final databasePath = await getDatabasesPath();
    final dbFile = p.join(databasePath, 'insurance_renewal_advisor.db');
    _db = await openDatabase(
      dbFile,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE $_table (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  srNo INTEGER NOT NULL,
  vehicleNumber TEXT NOT NULL,
  customerName TEXT NOT NULL,
  contactNumber TEXT NOT NULL,
  registrationDate TEXT NOT NULL,
  makeModel TEXT NOT NULL,
  insuranceCompany TEXT NOT NULL,
  policyNumber TEXT NOT NULL,
  policyStartDate TEXT NOT NULL,
  policyEndDate TEXT NOT NULL,
  policyType TEXT NOT NULL,
  premiumAmount REAL NOT NULL,
  renewalReminder TEXT NOT NULL,
  referenceContact TEXT NOT NULL,
  piDone INTEGER NOT NULL,
  agentName TEXT NOT NULL,
  rcDocument TEXT NOT NULL,
  policyDocument TEXT NOT NULL,
  kycDocument TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL
)
''');
      },
    );
  }

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('Database is not initialized');
    }
    return database;
  }

  Future<List<PolicyRecord>> listPolicies() async {
    final rows = await db.query(_table, orderBy: 'policyEndDate ASC, srNo ASC');
    return rows.map(PolicyRecord.fromMap).toList();
  }

  Future<int> nextSerial() async {
    final result = await db.rawQuery('SELECT MAX(srNo) as maxSerial FROM $_table');
    final maxSerial = PolicyRecord._asInt(result.first['maxSerial']);
    return maxSerial + 1;
  }

  Future<void> upsertPolicy(PolicyRecord policy) async {
    final now = DateTime.now();
    final normalized = PolicyRecord(
      id: policy.id,
      srNo: policy.srNo,
      vehicleNumber: policy.vehicleNumber.trim().toUpperCase(),
      customerName: policy.customerName.trim(),
      contactNumber: policy.contactNumber.trim(),
      registrationDate: policy.registrationDate,
      makeModel: policy.makeModel.trim(),
      insuranceCompany: policy.insuranceCompany.trim(),
      policyNumber: policy.policyNumber.trim(),
      policyStartDate: policy.policyStartDate,
      policyEndDate: policy.policyEndDate,
      policyType: policy.policyType,
      premiumAmount: policy.premiumAmount,
      referenceContact: policy.referenceContact.trim(),
      piDone: policy.piDone,
      agentName: policy.agentName.trim(),
      rcDocument: policy.rcDocument,
      policyDocument: policy.policyDocument,
      kycDocument: policy.kycDocument,
      createdAt: policy.createdAt,
      updatedAt: now,
    );

    if (normalized.id == null) {
      await db.insert(_table, normalized.toDbMap());
    } else {
      await db.update(
        _table,
        normalized.toDbMap(),
        where: 'id = ?',
        whereArgs: <Object?>[normalized.id],
      );
    }
  }

  Future<void> deletePolicy(int id) async {
    await db.delete(_table, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<File> exportBackup() async {
    final policies = await listPolicies();
    final directory = await _ensureExportDirectory('backups');
    final file = File(p.join(directory.path, 'policy_backup_${fileDate.format(DateTime.now())}.json'));
    final data = policies.map((policy) => policy.toDbMap(includeId: false)).toList();
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  Future<int> restoreBackup(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Backup file must contain a JSON list');
    }
    await db.transaction((txn) async {
      await txn.delete(_table);
      for (final entry in decoded) {
        if (entry is Map<String, Object?>) {
          final policy = PolicyRecord.fromMap(entry);
          await txn.insert(_table, policy.toDbMap());
        } else if (entry is Map) {
          final normalized = entry.map((key, value) => MapEntry('$key', value));
          final policy = PolicyRecord.fromMap(normalized);
          await txn.insert(_table, policy.toDbMap());
        }
      }
    });
    return decoded.length;
  }

  Future<File> exportPdf(List<PolicyRecord> policies) async {
    final directory = await _ensureExportDirectory('exports');
    final file = File(p.join(directory.path, 'policies_${fileDate.format(DateTime.now())}.pdf'));
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        build: (context) => <pw.Widget>[
          pw.Header(level: 0, child: pw.Text('Insurance Renewal Advisor')),
          pw.Text('Generated on ${compactDate.format(DateTime.now())}'),
          pw.SizedBox(height: 12),
          pw.Table.fromTextArray(
            headers: <String>[
              'Sr',
              'Vehicle',
              'Customer',
              'Contact',
              'Company',
              'Policy No',
              'End Date',
              'Status',
              'Premium',
            ],
            data: policies.map((policy) {
              return <String>[
                '${policy.srNo}',
                policy.vehicleNumber,
                policy.customerName,
                policy.contactNumber,
                policy.insuranceCompany,
                policy.policyNumber,
                compactDate.format(policy.policyEndDate),
                policy.statusLabel,
                policy.premiumAmount.toStringAsFixed(2),
              ];
            }).toList(),
          ),
        ],
      ),
    );
    await file.writeAsBytes(await document.save());
    return file;
  }

  Future<File> exportExcelCompatible(List<PolicyRecord> policies) async {
    final directory = await _ensureExportDirectory('exports');
    final file = File(p.join(directory.path, 'policies_${fileDate.format(DateTime.now())}.xls'));
    final buffer = StringBuffer()
      ..writeln('<html><head><meta charset="utf-8"></head><body>')
      ..writeln('<table border="1">')
      ..writeln('<tr>')
      ..writeln('<th>Sr No</th><th>Vehicle Number</th><th>Customer Name</th><th>Contact Number</th>')
      ..writeln('<th>Registration Date</th><th>Make Model</th><th>Insurance Company</th>')
      ..writeln('<th>Policy Number</th><th>Policy Start Date</th><th>Policy End Date</th>')
      ..writeln('<th>Policy Type</th><th>Premium Amount</th><th>Reminder Date</th>')
      ..writeln('<th>Reference Contact</th><th>PI Done</th><th>Agent</th><th>Status</th>')
      ..writeln('</tr>');
    for (final policy in policies) {
      final piText = policy.piDone ? 'Yes' : 'No';
      buffer
        ..writeln('<tr>')
        ..writeln('<td>${_html(policy.srNo)}</td>')
        ..writeln('<td>${_html(policy.vehicleNumber)}</td>')
        ..writeln('<td>${_html(policy.customerName)}</td>')
        ..writeln('<td>${_html(policy.contactNumber)}</td>')
        ..writeln('<td>${_html(compactDate.format(policy.registrationDate))}</td>')
        ..writeln('<td>${_html(policy.makeModel)}</td>')
        ..writeln('<td>${_html(policy.insuranceCompany)}</td>')
        ..writeln('<td>${_html(policy.policyNumber)}</td>')
        ..writeln('<td>${_html(compactDate.format(policy.policyStartDate))}</td>')
        ..writeln('<td>${_html(compactDate.format(policy.policyEndDate))}</td>')
        ..writeln('<td>${_html(policy.policyType)}</td>')
        ..writeln('<td>${policy.premiumAmount.toStringAsFixed(2)}</td>')
        ..writeln('<td>${_html(compactDate.format(policy.renewalReminder))}</td>')
        ..writeln('<td>${_html(policy.referenceContact)}</td>')
        ..writeln('<td>${_html(piText)}</td>')
        ..writeln('<td>${_html(policy.agentName)}</td>')
        ..writeln('<td>${_html(policy.statusLabel)}</td>')
        ..writeln('</tr>');
    }
    buffer.writeln('</table></body></html>');
    await file.writeAsString(buffer.toString());
    return file;
  }

  Future<Directory> _ensureExportDirectory(String name) async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, name));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static String _html(Object? value) {
    return const HtmlEscape().convert('${value ?? ''}');
  }
}

class RenewalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_notification'),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> syncDailyAlerts(List<PolicyRecord> policies) async {
    await _plugin.cancelAll();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'renewal_alerts',
        'Renewal alerts',
        channelDescription: 'Daily reminders for policies expiring within 15 days.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    for (final policy in policies.where((policy) => policy.status == PolicyStatus.expiringSoon)) {
      final id = 1000 + (policy.id ?? policy.srNo);
      await _plugin.periodicallyShow(
        id,
        'Policy expiring soon',
        '${policy.vehicleNumber} expires on ${compactDate.format(policy.policyEndDate)}',
        RepeatInterval.daily,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: '${policy.id}',
      );
    }
  }
}

class AuthStore {
  AuthStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<AuthStore> load() async {
    return AuthStore(await SharedPreferences.getInstance());
  }

  String get mobile => _prefs.getString('mobile') ?? '';
  String get pin => _prefs.getString('pin') ?? '';
  bool get isLoggedIn => mobile.isNotEmpty;
  bool get hasPin => pin.isNotEmpty;
  bool get darkMode => _prefs.getBool('darkMode') ?? false;

  Future<void> login(String mobileNumber) async {
    await _prefs.setString('mobile', mobileNumber);
  }

  Future<void> logout() async {
    await _prefs.remove('mobile');
  }

  Future<void> setPin(String value) async {
    if (value.isEmpty) {
      await _prefs.remove('pin');
      return;
    }
    await _prefs.setString('pin', value);
  }

  bool verifyPin(String value) => value == pin;

  Future<void> setDarkMode(bool enabled) async {
    await _prefs.setBool('darkMode', enabled);
  }
}

class AdvisorApp extends StatefulWidget {
  const AdvisorApp({
    super.key,
    required this.repository,
    required this.notifications,
  });

  final PolicyRepository repository;
  final RenewalNotificationService notifications;

  @override
  State<AdvisorApp> createState() => _AdvisorAppState();
}

class _AdvisorAppState extends State<AdvisorApp> {
  AuthStore? _auth;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _auth = await AuthStore.load();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setDarkMode(bool value) async {
    await _auth?.setDarkMode(value);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = _auth;
    final seed = const Color(0xFF1565C0);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Insurance Renewal Advisor',
      themeMode: auth?.darkMode == true ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        visualDensity: VisualDensity.standard,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
      ),
      home: auth == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : AuthGate(
              auth: auth,
              repository: widget.repository,
              notifications: widget.notifications,
              onDarkModeChanged: _setDarkMode,
              onAuthChanged: () => setState(() {}),
            ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.auth,
    required this.repository,
    required this.notifications,
    required this.onDarkModeChanged,
    required this.onAuthChanged,
  });

  final AuthStore auth;
  final PolicyRepository repository;
  final RenewalNotificationService notifications;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onAuthChanged;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _pinUnlocked = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.auth.isLoggedIn) {
      return LoginPage(
        auth: widget.auth,
        onAuthenticated: () {
          setState(() => _pinUnlocked = !widget.auth.hasPin);
          widget.onAuthChanged();
        },
      );
    }
    if (widget.auth.hasPin && !_pinUnlocked) {
      return PinUnlockPage(
        auth: widget.auth,
        onUnlocked: () => setState(() => _pinUnlocked = true),
      );
    }
    return HomeShell(
      auth: widget.auth,
      repository: widget.repository,
      notifications: widget.notifications,
      onDarkModeChanged: widget.onDarkModeChanged,
      onLogout: () {
        setState(() => _pinUnlocked = false);
        widget.onAuthChanged();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.auth,
    required this.onAuthenticated,
  });

  final AuthStore auth;
  final VoidCallback onAuthenticated;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _mobile = TextEditingController();
  final TextEditingController _otp = TextEditingController();
  final TextEditingController _pin = TextEditingController();
  String _generatedOtp = '';

  @override
  void dispose() {
    _mobile.dispose();
    _otp.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _sendOtp() {
    if (_mobile.text.trim().length < 10) {
      _showMessage(context, 'Enter a valid mobile number');
      return;
    }
    final seed = DateTime.now().millisecondsSinceEpoch % 900000;
    setState(() => _generatedOtp = '${100000 + seed}');
    _showMessage(context, 'Demo OTP: $_generatedOtp');
  }

  Future<void> _verify() async {
    if (_generatedOtp.isEmpty) {
      _showMessage(context, 'Send OTP first');
      return;
    }
    if (_otp.text.trim() != _generatedOtp) {
      _showMessage(context, 'Incorrect OTP');
      return;
    }
    if (_pin.text.isNotEmpty && _pin.text.length < 4) {
      _showMessage(context, 'PIN must be at least 4 digits');
      return;
    }
    await widget.auth.login(_mobile.text.trim());
    if (_pin.text.isNotEmpty) {
      await widget.auth.setPin(_pin.text);
    }
    widget.onAuthenticated();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(Icons.policy_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 20),
                  Text(
                    'Insurance Renewal Advisor',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Login with mobile OTP and keep policy data offline on this device.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _mobile,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Mobile number',
                      prefixIcon: Icon(Icons.phone_android),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _sendOtp,
                    icon: const Icon(Icons.sms_outlined),
                    label: const Text('Send OTP'),
                  ),
                  if (_generatedOtp.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'OTP',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Optional app PIN',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _verify,
                      child: const Text('Verify and continue'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PinUnlockPage extends StatefulWidget {
  const PinUnlockPage({
    super.key,
    required this.auth,
    required this.onUnlocked,
  });

  final AuthStore auth;
  final VoidCallback onUnlocked;

  @override
  State<PinUnlockPage> createState() => _PinUnlockPageState();
}

class _PinUnlockPageState extends State<PinUnlockPage> {
  final TextEditingController _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _unlock() {
    if (widget.auth.verifyPin(_pin.text)) {
      widget.onUnlocked();
    } else {
      _showMessage(context, 'Incorrect PIN');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Icon(Icons.lock_outline, size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text('Unlock app', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    onSubmitted: (_) => _unlock(),
                    decoration: const InputDecoration(labelText: 'PIN', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _unlock, child: const Text('Unlock')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.auth,
    required this.repository,
    required this.notifications,
    required this.onDarkModeChanged,
    required this.onLogout,
  });

  final AuthStore auth;
  final PolicyRepository repository;
  final RenewalNotificationService notifications;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onLogout;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  List<PolicyRecord> _policies = <PolicyRecord>[];
  String _query = '';
  String _filter = 'All';
  String _companyFilter = 'All companies';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final policies = await widget.repository.listPolicies();
    await widget.notifications.syncDailyAlerts(policies);
    if (mounted) {
      setState(() {
        _policies = policies;
        _loading = false;
      });
    }
  }

  List<PolicyRecord> get _filtered {
    final normalizedQuery = _query.trim().toLowerCase();
    return _policies.where((policy) {
      final matchesQuery = normalizedQuery.isEmpty ||
          policy.vehicleNumber.toLowerCase().contains(normalizedQuery) ||
          policy.customerName.toLowerCase().contains(normalizedQuery);
      final matchesFilter = switch (_filter) {
        'Expiring soon' => policy.status == PolicyStatus.expiringSoon,
        'Active' => policy.isActive,
        'Expired' => policy.status == PolicyStatus.expired,
        _ => true,
      };
      final matchesCompany = _companyFilter == 'All companies' || policy.insuranceCompany == _companyFilter;
      return matchesQuery && matchesFilter && matchesCompany;
    }).toList();
  }

  List<String> get _companies {
    final names = _policies.map((policy) => policy.insuranceCompany).where((name) => name.isNotEmpty).toSet().toList()
      ..sort();
    return <String>['All companies', ...names];
  }

  Future<void> _openForm([PolicyRecord? policy]) async {
    final nextSerial = await widget.repository.nextSerial();
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PolicyFormPage(
          repository: widget.repository,
          initialSerial: nextSerial,
          policy: policy,
        ),
      ),
    );
    if (saved == true) {
      await _refresh();
      if (mounted) {
        _showMessage(context, 'Policy saved');
      }
    }
  }

  Future<void> _delete(PolicyRecord policy) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete policy?'),
        content: Text('Remove ${policy.vehicleNumber} for ${policy.customerName}?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && policy.id != null) {
      await widget.repository.deletePolicy(policy.id!);
      await _refresh();
    }
  }

  Future<void> _shareFile(Future<File> Function() action, String label) async {
    try {
      final file = await action();
      await Share.shareXFiles(<XFile>[XFile(file.path)], text: label);
      if (mounted) {
        _showMessage(context, 'Created ${p.basename(file.path)}');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(context, 'Export failed: $error');
      }
    }
  }

  Future<void> _restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    final path = result?.files.single.path;
    if (path == null) {
      return;
    }
    try {
      final count = await widget.repository.restoreBackup(File(path));
      await _refresh();
      if (mounted) {
        _showMessage(context, 'Restored $count policies');
      }
    } catch (error) {
      if (mounted) {
        _showMessage(context, 'Restore failed: $error');
      }
    }
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SettingsSheet(
        auth: widget.auth,
        onDarkModeChanged: widget.onDarkModeChanged,
        onExportPdf: () => _shareFile(() => widget.repository.exportPdf(_filtered), 'Policy PDF export'),
        onExportExcel: () => _shareFile(
          () => widget.repository.exportExcelCompatible(_filtered),
          'Policy Excel-compatible export',
        ),
        onBackup: () => _shareFile(widget.repository.exportBackup, 'Policy backup'),
        onRestore: _restoreBackup,
        onLogout: () async {
          await widget.auth.logout();
          if (mounted) {
            Navigator.pop(context);
            widget.onLogout();
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expiring = _policies.where((policy) => policy.status == PolicyStatus.expiringSoon).length;
    final expired = _policies.where((policy) => policy.status == PolicyStatus.expired).length;
    final active = _policies.where((policy) => policy.isActive).length;
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Renewals'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Add policy'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: <Widget>[
                  DashboardSummary(
                    total: _policies.length,
                    expiring: expiring,
                    active: active,
                    expired: expired,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      labelText: 'Search vehicle or customer',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <String>['All', 'Expiring soon', 'Active', 'Expired'].map((name) {
                      return ChoiceChip(
                        label: Text(name),
                        selected: _filter == name,
                        onSelected: (_) => setState(() => _filter = name),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _companies.contains(_companyFilter) ? _companyFilter : 'All companies',
                    items: _companies
                        .map((company) => DropdownMenuItem<String>(value: company, child: Text(company)))
                        .toList(),
                    onChanged: (value) => setState(() => _companyFilter = value ?? 'All companies'),
                    decoration: const InputDecoration(
                      labelText: 'Insurance company',
                      prefixIcon: Icon(Icons.business_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    EmptyState(hasPolicies: _policies.isNotEmpty)
                  else
                    ...filtered.map(
                      (policy) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PolicyCard(
                          policy: policy,
                          onEdit: () => _openForm(policy),
                          onDelete: () => _delete(policy),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class DashboardSummary extends StatelessWidget {
  const DashboardSummary({
    super.key,
    required this.total,
    required this.expiring,
    required this.active,
    required this.expired,
  });

  final int total;
  final int expiring;
  final int active;
  final int expired;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.sizeOf(context).width > 720 ? 4 : 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.65,
      children: <Widget>[
        MetricTile(label: 'Total vehicles', value: total, icon: Icons.directions_car_outlined),
        MetricTile(label: 'Expiring in 15 days', value: expiring, icon: Icons.warning_amber, alert: true),
        MetricTile(label: 'Active policies', value: active, icon: Icons.verified_outlined),
        MetricTile(label: 'Expired policies', value: expired, icon: Icons.event_busy_outlined),
      ],
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.alert = false,
  });

  final String label;
  final int value;
  final IconData icon;
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final color = alert ? Colors.red.shade700 : Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 0,
      color: alert ? Colors.red.withOpacity(0.08) : Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Icon(icon, color: color),
            Text('$value', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.hasPolicies});

  final bool hasPolicies;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Column(
        children: <Widget>[
          Icon(Icons.inventory_2_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            hasPolicies ? 'No policies match this filter' : 'Add your first vehicle policy',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class PolicyCard extends StatelessWidget {
  const PolicyCard({
    super.key,
    required this.policy,
    required this.onEdit,
    required this.onDelete,
  });

  final PolicyRecord policy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Future<void> _launchWhatsApp(BuildContext context) async {
    final phone = _normalizedPhone(policy.contactNumber);
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(policy.reminderMessage)}');
    await _launchExternal(context, uri);
  }

  Future<void> _launchSms(BuildContext context) async {
    final uri = Uri(
      scheme: 'sms',
      path: _normalizedPhone(policy.contactNumber),
      queryParameters: <String, String>{'body': policy.reminderMessage},
    );
    await _launchExternal(context, uri);
  }

  static String _normalizedPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      return '91$digits';
    }
    return digits;
  }

  static Future<void> _launchExternal(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        _showMessage(context, 'Unable to open ${uri.scheme}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = policy.statusColor(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        policy.vehicleNumber,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(policy.customerName),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                StatusPill(label: policy.statusLabel, color: statusColor),
                StatusPill(label: '${policy.daysUntilExpiry} days', color: statusColor),
                StatusPill(label: policy.policyType, color: Theme.of(context).colorScheme.primary),
              ],
            ),
            const SizedBox(height: 12),
            InfoRow(icon: Icons.business_outlined, text: policy.insuranceCompany),
            InfoRow(icon: Icons.description_outlined, text: 'Policy ${policy.policyNumber}'),
            InfoRow(icon: Icons.event_outlined, text: 'Ends ${compactDate.format(policy.policyEndDate)}'),
            InfoRow(icon: Icons.currency_rupee, text: policy.premiumAmount.toStringAsFixed(2)),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                IconButton.filledTonal(
                  tooltip: 'WhatsApp reminder',
                  onPressed: () => _launchWhatsApp(context),
                  icon: const Icon(Icons.chat_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'SMS reminder',
                  onPressed: () => _launchSms(context),
                  icon: const Icon(Icons.sms_outlined),
                ),
                const Spacer(),
                TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(child: Text(text, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({
    super.key,
    required this.auth,
    required this.onDarkModeChanged,
    required this.onExportPdf,
    required this.onExportExcel,
    required this.onBackup,
    required this.onRestore,
    required this.onLogout,
  });

  final AuthStore auth;
  final ValueChanged<bool> onDarkModeChanged;
  final VoidCallback onExportPdf;
  final VoidCallback onExportExcel;
  final VoidCallback onBackup;
  final VoidCallback onRestore;
  final VoidCallback onLogout;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  final TextEditingController _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _savePin() async {
    await widget.auth.setPin(_pin.text.trim());
    if (mounted) {
      _showMessage(context, _pin.text.trim().isEmpty ? 'PIN removed' : 'PIN updated');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: <Widget>[
          Text('Tools', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark mode'),
            value: widget.auth.darkMode,
            onChanged: (value) {
              setState(() {});
              widget.onDarkModeChanged(value);
            },
          ),
          TextField(
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Set or clear app PIN',
              border: OutlineInputBorder(),
              helperText: 'Leave empty to remove the PIN lock.',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: _savePin, icon: const Icon(Icons.lock_outline), label: const Text('Save PIN')),
          const Divider(height: 28),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: const Text('Export PDF'),
            onTap: widget.onExportPdf,
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export Excel-compatible file'),
            onTap: widget.onExportExcel,
          ),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Backup data'),
            onTap: widget.onBackup,
          ),
          ListTile(
            leading: const Icon(Icons.restore_outlined),
            title: const Text('Restore data'),
            onTap: widget.onRestore,
          ),
          const Divider(height: 28),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Log out'),
            onTap: widget.onLogout,
          ),
        ],
      ),
    );
  }
}

class PolicyFormPage extends StatefulWidget {
  const PolicyFormPage({
    super.key,
    required this.repository,
    required this.initialSerial,
    this.policy,
  });

  final PolicyRepository repository;
  final int initialSerial;
  final PolicyRecord? policy;

  @override
  State<PolicyFormPage> createState() => _PolicyFormPageState();
}

class _PolicyFormPageState extends State<PolicyFormPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _srNo;
  late final TextEditingController _vehicleNumber;
  late final TextEditingController _customerName;
  late final TextEditingController _contactNumber;
  late final TextEditingController _makeModel;
  late final TextEditingController _insuranceCompany;
  late final TextEditingController _policyNumber;
  late final TextEditingController _premiumAmount;
  late final TextEditingController _referenceContact;
  late final TextEditingController _agentName;

  late DateTime _registrationDate;
  late DateTime _startDate;
  late DateTime _endDate;
  late String _policyType;
  late bool _piDone;
  late String _rcDocument;
  late String _policyDocument;
  late String _kycDocument;

  @override
  void initState() {
    super.initState();
    final policy = widget.policy;
    _srNo = TextEditingController(text: '${policy?.srNo ?? widget.initialSerial}');
    _vehicleNumber = TextEditingController(text: policy?.vehicleNumber ?? '');
    _customerName = TextEditingController(text: policy?.customerName ?? '');
    _contactNumber = TextEditingController(text: policy?.contactNumber ?? '');
    _makeModel = TextEditingController(text: policy?.makeModel ?? '');
    _insuranceCompany = TextEditingController(text: policy?.insuranceCompany ?? '');
    _policyNumber = TextEditingController(text: policy?.policyNumber ?? '');
    _premiumAmount = TextEditingController(text: policy == null ? '' : policy.premiumAmount.toStringAsFixed(2));
    _referenceContact = TextEditingController(text: policy?.referenceContact ?? '');
    _agentName = TextEditingController(text: policy?.agentName ?? '');
    _registrationDate = policy?.registrationDate ?? DateTime.now();
    _startDate = policy?.policyStartDate ?? DateTime.now();
    _endDate = policy?.policyEndDate ?? DateTime.now().add(const Duration(days: 365));
    _policyType = policy?.policyType ?? policyTypes.first;
    _piDone = policy?.piDone ?? false;
    _rcDocument = policy?.rcDocument ?? '';
    _policyDocument = policy?.policyDocument ?? '';
    _kycDocument = policy?.kycDocument ?? '';
  }

  @override
  void dispose() {
    _srNo.dispose();
    _vehicleNumber.dispose();
    _customerName.dispose();
    _contactNumber.dispose();
    _makeModel.dispose();
    _insuranceCompany.dispose();
    _policyNumber.dispose();
    _premiumAmount.dispose();
    _referenceContact.dispose();
    _agentName.dispose();
    super.dispose();
  }

  Future<void> _pickDate(DateTime current, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
      initialDate: current,
    );
    if (picked != null) {
      onPicked(picked);
    }
  }

  Future<void> _pickDocument(ValueChanged<String> onPicked) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf', 'jpg', 'jpeg', 'png'],
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null) {
      return;
    }
    final base = await getApplicationDocumentsDirectory();
    final docs = Directory(p.join(base.path, 'policy_documents'));
    if (!docs.existsSync()) {
      await docs.create(recursive: true);
    }
    final source = File(sourcePath);
    final copy = await source.copy(
      p.join(docs.path, '${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourcePath)}'),
    );
    onPicked(copy.path);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_endDate.isBefore(_startDate)) {
      _showMessage(context, 'Policy end date must be after start date');
      return;
    }
    final now = DateTime.now();
    final policy = PolicyRecord(
      id: widget.policy?.id,
      srNo: int.tryParse(_srNo.text.trim()) ?? widget.initialSerial,
      vehicleNumber: _vehicleNumber.text,
      customerName: _customerName.text,
      contactNumber: _contactNumber.text,
      registrationDate: _registrationDate,
      makeModel: _makeModel.text,
      insuranceCompany: _insuranceCompany.text,
      policyNumber: _policyNumber.text,
      policyStartDate: _startDate,
      policyEndDate: _endDate,
      policyType: _policyType,
      premiumAmount: double.tryParse(_premiumAmount.text.trim()) ?? 0,
      referenceContact: _referenceContact.text,
      piDone: _piDone,
      agentName: _agentName.text,
      rcDocument: _rcDocument,
      policyDocument: _policyDocument,
      kycDocument: _kycDocument,
      createdAt: widget.policy?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.repository.upsertPolicy(policy);
    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminderDate = _endDate.subtract(const Duration(days: 15));
    return Scaffold(
      appBar: AppBar(title: Text(widget.policy == null ? 'Add policy' : 'Edit policy')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: <Widget>[
            SectionTitle(title: 'Vehicle and customer'),
            AppTextField(controller: _srNo, label: 'Sr No', keyboardType: TextInputType.number),
            AppTextField(controller: _vehicleNumber, label: 'Vehicle Number', requiredField: true),
            AppTextField(controller: _customerName, label: 'Customer Name', requiredField: true),
            AppTextField(
              controller: _contactNumber,
              label: 'Contact Number',
              requiredField: true,
              keyboardType: TextInputType.phone,
            ),
            DateTile(
              label: 'Registration Date',
              value: _registrationDate,
              onTap: () => _pickDate(_registrationDate, (value) => setState(() => _registrationDate = value)),
            ),
            AppTextField(controller: _makeModel, label: 'Make & Model', requiredField: true),
            const SizedBox(height: 12),
            SectionTitle(title: 'Policy details'),
            AppTextField(
              controller: _insuranceCompany,
              label: 'Insurance Company Name',
              requiredField: true,
            ),
            AppTextField(controller: _policyNumber, label: 'Policy Number', requiredField: true),
            DateTile(
              label: 'Policy Start Date',
              value: _startDate,
              onTap: () => _pickDate(_startDate, (value) => setState(() => _startDate = value)),
            ),
            DateTile(
              label: 'Policy End Date',
              value: _endDate,
              onTap: () => _pickDate(_endDate, (value) => setState(() => _endDate = value)),
            ),
            DropdownButtonFormField<String>(
              value: _policyType,
              items: policyTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
              onChanged: (value) => setState(() => _policyType = value ?? policyTypes.first),
              decoration: const InputDecoration(labelText: 'Policy Type', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _premiumAmount,
              label: 'Premium Amount',
              requiredField: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Renewal Reminder'),
              subtitle: Text('${compactDate.format(reminderDate)} (15 days before expiry)'),
            ),
            AppTextField(
              controller: _referenceContact,
              label: 'Reference Person Contact',
              keyboardType: TextInputType.phone,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('PI Done'),
              value: _piDone,
              onChanged: (value) => setState(() => _piDone = value),
            ),
            AppTextField(controller: _agentName, label: 'Policy Agent Name', requiredField: true),
            const SizedBox(height: 12),
            SectionTitle(title: 'Documents'),
            DocumentTile(
              label: 'Upload RC',
              path: _rcDocument,
              onPick: () => _pickDocument((path) => setState(() => _rcDocument = path)),
              onClear: () => setState(() => _rcDocument = ''),
            ),
            DocumentTile(
              label: 'Upload Insurance Policy',
              path: _policyDocument,
              onPick: () => _pickDocument((path) => setState(() => _policyDocument = path)),
              onClear: () => setState(() => _policyDocument = ''),
            ),
            DocumentTile(
              label: 'Upload KYC',
              path: _kycDocument,
              onPick: () => _pickDocument((path) => setState(() => _kycDocument = path)),
              onClear: () => setState(() => _kycDocument = ''),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save policy'),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.requiredField = false,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final bool requiredField;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: (value) {
          if (requiredField && (value == null || value.trim().isEmpty)) {
            return '$label is required';
          }
          return null;
        },
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }
}

class DateTile extends StatelessWidget {
  const DateTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        leading: const Icon(Icons.calendar_today_outlined),
        title: Text(label),
        subtitle: Text(compactDate.format(value)),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: onTap,
      ),
    );
  }
}

class DocumentTile extends StatelessWidget {
  const DocumentTile({
    super.key,
    required this.label,
    required this.path,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String path;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final hasFile = path.isNotEmpty;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(hasFile ? Icons.check_circle_outline : Icons.upload_file_outlined),
        title: Text(label),
        subtitle: Text(hasFile ? p.basename(path) : 'Image or PDF'),
        trailing: hasFile
            ? IconButton(tooltip: 'Remove file', onPressed: onClear, icon: const Icon(Icons.close))
            : IconButton(tooltip: 'Choose file', onPressed: onPick, icon: const Icon(Icons.add)),
        onTap: onPick,
      ),
    );
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
