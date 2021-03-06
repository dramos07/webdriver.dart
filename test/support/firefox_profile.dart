// Copyright 2015 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@TestOn("vm")
library webdriver.support.firefox_profile_test;

import 'dart:convert' show BASE64, Encoding, UTF8;
import 'dart:io' as io;
import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipDecoder;
import 'package:test/test.dart';
import 'package:webdriver/core.dart';
import 'package:webdriver/support/firefox_profile.dart';

void runTests() {
  group('Firefox profile', () {
    test('parse and serialize string value with quotes', () {
      const value =
          r'user_pref("extensions.xpiState", "{\"app-global\":{\"{972ce4c6-'
          r'7e08-4474-a285-3208198ce6fd}\":{\"d\":\"/opt/firefox/browser/'
          r'extensions/{972ce4c6-7e08-4474-a285-3208198ce6fd}\",\"e\":true,\'
          r'"v\":\"40.0\",\"st\":1439535413000,\"mt\":1438968709000}}}");';
      var option = new PrefsOption.parse(value);
      expect(option, new isInstanceOf<StringOption>());
      expect(option.asPrefString, value);
    });

    test('parse and serialize string value with backslash', () {
      const value = r'user_pref("browser.cache.disk.parent_directory", '
          r'"\\\\volume\\web\\cache\\mz");';
      var option = new PrefsOption.parse(value);
      expect(option, new isInstanceOf<StringOption>());
      expect(option.asPrefString, value);
    });

    test('parse and serialize integer value', () {
      const value = r'user_pref("browser.cache.frecency_experiment", 3);';
      var option = new PrefsOption.parse(value);
      expect(option, new isInstanceOf<IntegerOption>());
      expect(option.asPrefString, value);
    });

    test('parse and serialize negative integer value', () {
      const value = r'user_pref("browser.cache.frecency_experiment", -3);';
      var option = new PrefsOption.parse(value);
      expect(option, new isInstanceOf<IntegerOption>());
      expect(option.asPrefString, value);
    });

    test('parse and serialize boolean true', () {
      const value =
          r'user_pref("browser.cache.disk.smart_size.first_run", true);';
      var option = new PrefsOption.parse(value);
      expect(option, new isInstanceOf<BooleanOption>());
      expect(option.asPrefString, value);
    });

    test('parse and serialize boolean false', () {
      const value =
          r'user_pref("browser.cache.disk.smart_size.first_run", false);';
      var option = new PrefsOption.parse(value);
      expect(option, new isInstanceOf<BooleanOption>());
      expect(option.asPrefString, value);
    });

    test('parse boolean uppercase True', () {
      const value =
          r'user_pref("browser.cache.disk.smart_size.first_run", True);';
      var option = new PrefsOption.parse(value);
      expect(option, new isInstanceOf<BooleanOption>());
      expect(option.value, true);
    });

    test('added value should be in prefs', () {
      var profile = new FirefoxProfile();
      var option =
          new PrefsOption('browser.bookmarks.restore_default_bookmarks', false);

      expect(profile.setOption(option), true);

      expect(
          profile.userPrefs,
          anyElement((PrefsOption e) =>
              e.name == option.name && e.value == option.value));
    });

    test('overriding locked value should be ignored', () {
      var profile = new FirefoxProfile();
      var lockedOption = new PrefsOption('javascript.enabled', false);
      var lockedOptionOrig =
          profile.prefs.firstWhere((e) => e.name == lockedOption.name);
      expect(lockedOption.value, isNot(lockedOptionOrig.value));

      expect(profile.setOption(lockedOption), false);

      expect(profile.userPrefs, isNot(anyElement(lockedOption)));
      expect(profile.prefs.firstWhere((e) => e.name == lockedOption.name).value,
          lockedOptionOrig.value);
    });

    test('removing locked value should be ignored', () {
      var profile = new FirefoxProfile();
      var lockedOption = new PrefsOption('javascript.enabled', false);
      var lockedOptionOrig =
          profile.prefs.firstWhere((e) => e.name == lockedOption.name);
      expect(lockedOption.value, isNot(lockedOptionOrig.value));

      expect(profile.removeOption(lockedOption.name), false);

      expect(profile.userPrefs, isNot(anyElement(lockedOption)));
      expect(profile.prefs.firstWhere((e) => e.name == lockedOption.name).value,
          lockedOptionOrig.value);
    });

    test('encode/decode "user.js" in-memory', () {
      var profile = new FirefoxProfile();
      profile.setOption(new PrefsOption(Capabilities.hasNativeEvents, true));

      var archive = unpackArchiveData(profile.toJson());

      var expectedFiles = ['prefs.js', 'user.js'];
      expect(archive.files.length, greaterThanOrEqualTo(expectedFiles.length));
      expectedFiles.forEach((f) => expect(
          archive.files, anyElement((ArchiveFile f) => f.name == 'prefs.js')));

      var prefs = FirefoxProfile.loadPrefsFile(new MockFile(
          new String.fromCharCodes(
              archive.files.firstWhere((f) => f.name == 'user.js').content)));
      expect(
          prefs,
          anyElement((PrefsOption o) =>
              o.name == Capabilities.hasNativeEvents && o.value == true));
    });

    test('encode/decode profile directory from disk', () {
      var profile = new FirefoxProfile(
          profileDirectory: new io.Directory('test/support/firefox_profile'));
      profile.setOption(new PrefsOption(Capabilities.hasNativeEvents, true));

      var archive = unpackArchiveData(profile.toJson());

      var expectedFiles = [
        'prefs.js',
        'user.js',
        'addons.js',
        'webapps/',
        'webapps/webapps.json'
      ];
      expect(archive.files.length, greaterThanOrEqualTo(expectedFiles.length));
      expectedFiles.forEach((f) => expect(
          archive.files, anyElement((ArchiveFile f) => f.name == 'prefs.js')));

      var prefs = FirefoxProfile.loadPrefsFile(new MockFile(
          new String.fromCharCodes(
              archive.files.firstWhere((f) => f.name == 'user.js').content)));
      expect(
          prefs,
          anyElement((PrefsOption o) =>
              o.name == Capabilities.hasNativeEvents && o.value == true));
    });
  });
}

Archive unpackArchiveData(Map profileData) {
  var zipArchive = BASE64.decode(profileData['firefox_profile']);
  return new ZipDecoder().decodeBytes(zipArchive, verify: true);
}

/// Simulate file for `FirefoxProfile.loadPrefsFile()`
class MockFile implements io.File {
  String content;

  MockFile(this.content);

  @override
  String readAsStringSync({Encoding encoding: UTF8}) => content;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
