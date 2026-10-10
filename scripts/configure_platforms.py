#!/usr/bin/env python3
"""Apply local-auth and privacy settings to Flutter-generated native projects.

Run after `flutter create --platforms=android,ios ... .`.
Idempotent on a standard Flutter 3.38+ skeleton.
"""
from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]

manifest = root / 'android/app/src/main/AndroidManifest.xml'
if manifest.exists():
    txt = manifest.read_text()
    if 'android.permission.USE_BIOMETRIC' not in txt:
        txt = re.sub(r'(<manifest\b[^>]*>)',
            r'\1\n    <uses-permission android:name="android.permission.USE_BIOMETRIC" />',
            txt, count=1)
    if 'android:allowBackup=' not in txt:
        txt = txt.replace('<application\n', '<application\n        android:allowBackup="false"\n        android:fullBackupContent="@xml/backup_rules"\n        android:dataExtractionRules="@xml/data_extraction_rules"\n', 1)
    manifest.write_text(txt)
    for gradle in (root / 'android/app/build.gradle.kts',):
        if gradle.exists():
            gs = gradle.read_text()
            gs = gs.replace('minSdk = flutter.minSdkVersion', 'minSdk = maxOf(flutter.minSdkVersion, 24)')
            # local_auth requires an AppCompat launch theme for legacy Android
            # versions; explicitly depend on AndroidX AppCompat so AAPT can
            # resolve Theme.AppCompat.DayNight.
            if 'implementation("androidx.appcompat:appcompat:' not in gs:
                gs += '\n\ndependencies {\n    implementation("androidx.appcompat:appcompat:1.7.1")\n}\n'
            gradle.write_text(gs)
    for activity in root.glob('android/app/src/main/**/*MainActivity.kt'):
        s = activity.read_text().replace('io.flutter.embedding.android.FlutterActivity',
            'io.flutter.embedding.android.FlutterFragmentActivity')
        s = re.sub(r'\bFlutterActivity\b', 'FlutterFragmentActivity', s)
        activity.write_text(s)
    for activity in root.glob('android/app/src/main/**/*MainActivity.java'):
        s = activity.read_text().replace('io.flutter.embedding.android.FlutterActivity',
            'io.flutter.embedding.android.FlutterFragmentActivity')
        s = re.sub(r'\bFlutterActivity\b', 'FlutterFragmentActivity', s)
        activity.write_text(s)
    for style in root.glob('android/app/src/main/res/values*/styles.xml'):
        s = style.read_text()
        s = re.sub(r'(<style name="LaunchTheme" parent=")[^"]+',
            r'\g<1>Theme.AppCompat.DayNight', s)
        style.write_text(s)
    xml_dir = root / 'android/app/src/main/res/xml'
    xml_dir.mkdir(parents=True, exist_ok=True)
    (xml_dir / 'backup_rules.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <exclude domain="root" path="." />
</full-backup-content>
''')
    (xml_dir / 'data_extraction_rules.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup><exclude domain="root" path="." /></cloud-backup>
    <device-transfer><exclude domain="root" path="." /></device-transfer>
</data-extraction-rules>
''')
    print('Android: biometric auth, FragmentActivity, backups disabled')
else:
    print('Android project missing; run flutter create first.')

info = root / 'ios/Runner/Info.plist'
if info.exists():
    with info.open('rb') as f:
        data = plistlib.load(f)
    data['NSFaceIDUsageDescription'] = 'Unlock your private offline budget.'
    data['UIFileSharingEnabled'] = False
    with info.open('wb') as f:
        plistlib.dump(data, f, sort_keys=False)
    app_delegate = root / 'ios/Runner/AppDelegate.swift'
    if app_delegate.exists():
        s = app_delegate.read_text()
        if 'isExcludedFromBackupKey' not in s:
            marker = 'GeneratedPluginRegistrant.register(with: self)'
            addition = '''\n    // Budget files are intentionally kept out of iCloud/device backups.\n    if var supportURL = FileManager.default.urls(\n      for: .applicationSupportDirectory, in: .userDomainMask).first {\n      try? FileManager.default.createDirectory(\n        at: supportURL, withIntermediateDirectories: true)\n      try? supportURL.setResourceValue(true, forKey: .isExcludedFromBackupKey)\n    }\n'''
            if marker not in s:
                raise RuntimeError('Cannot locate iOS plugin registration in AppDelegate.swift')
            s = s.replace(marker, marker + addition)
            app_delegate.write_text(s)
    pbx = root / 'ios/Runner.xcodeproj/project.pbxproj'
    if pbx.exists():
        s = pbx.read_text()
        s = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 14.0;', s)
        pbx.write_text(s)
    podfile = root / 'ios/Podfile'
    if podfile.exists():
        s = podfile.read_text()
        s = re.sub(r"^#?\s*platform :ios, '[0-9.]+'", "platform :ios, '14.0'", s, flags=re.MULTILINE)
        if 'platform :ios' not in s:
            s = "platform :ios, '14.0'\n" + s
        podfile.write_text(s)
    print('iOS: Face ID description, no file sharing, app-support backup exclusion')
else:
    print('iOS project missing; run flutter create first.')
