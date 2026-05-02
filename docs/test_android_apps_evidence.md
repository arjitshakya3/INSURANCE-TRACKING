# Test Android Apps Evidence

Date: 2026-05-02

## Requested Work

Use the Test Android Apps emulator workflow to reproduce an emulator issue and capture screenshots, logs, UI state, and performance evidence for the Android app.

## Local Tooling Preflight

The workspace is empty except for the app files created in this task. Required Android build and emulator tools were not available on PATH.

Observed command results:

```text
flutter --version
flutter : The term 'flutter' is not recognized as the name of a cmdlet, function, script file, or operable program.
```

```text
flutter pub get
flutter : The term 'flutter' is not recognized as the name of a cmdlet, function, script file, or operable program.
```

```text
flutter build apk --debug
flutter : The term 'flutter' is not recognized as the name of a cmdlet, function, script file, or operable program.
```

```text
where.exe adb
INFO: Could not find files for the given pattern(s).
```

```text
adb devices
adb : The term 'adb' is not recognized as the name of a cmdlet, function, script file, or operable program.
```

```text
where.exe java
INFO: Could not find files for the given pattern(s).
```

```text
where.exe npm
INFO: Could not find files for the given pattern(s).
```

Only the Codex-bundled `node.exe` was visible. No Android SDK, Flutter SDK, Java/JDK, Gradle, `adb.exe`, `npm`, `npx`, `winget`, `choco`, or `scoop` was found.

## Result

APK build, emulator installation, screenshots, UIAutomator state, logcat, `gfxinfo`, `meminfo`, Simpleperf, and Perfetto captures are blocked until Android tooling is installed or exposed to this workspace.

## Exact Evidence To Capture Once Tooling Exists

- Screenshot: dashboard after adding a policy that expires within 15 days.
- UI state: UIAutomator XML for login, dashboard, and policy form.
- Logs: filtered logcat for `com.advisor.insurance_renewal`.
- Frame evidence: `dumpsys gfxinfo com.advisor.insurance_renewal` after the add-policy flow.
- Memory evidence: `dumpsys meminfo com.advisor.insurance_renewal` from the idle dashboard.
- Optional CPU trace: Simpleperf profile for login and policy creation if the debug build is installed.
