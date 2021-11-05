import 'dart:io';

import 'package:args/args.dart';
import 'package:dcli/dcli.dart' hide Settings;
import 'package:dcli/dcli.dart' as dcli;

import 'critical_test_settings.dart';
import 'unit_tests/failed_tracker.dart';

late final defaultLogPath =
    '${Directory.systemTemp.path}/critical_test/unit_test.log';

class ParsedArgs {
  late final ArgParser parser;

  late final bool menu;

  late final String pathToProjectRoot;

  late final bool coverage;

  late final bool warmup;

  late final bool hooks;

  late final String trackerFilename;

  late final bool runFailed;

  late final List<String> tags;

  late final List<String> excludeTags;

  late final String plainName;

  late final bool track;

  late final ArgResults parsed;

  late final bool showSuccess;

  late final bool showProgress;

  late final String logPath;

  ParsedArgs.build() {
    parser = ArgParser()
      ..addFlag(
        'help',
        abbr: 'h',
        negatable: false,
        help: 'Shows this usage message.',
      )
      ..addOption('plain-name', abbr: 'N', help: 'Run a unit test by name.')
      ..addFlag('runfailed',
          abbr: 'f',
          negatable: false,
          help:
              'Re-runs only those tests that failed during the last run of critical_test.')
      ..addMultiOption('tags',
          abbr: 't',
          help:
              'Select  unit tests to run via their tags. The syntax must confirm to the --tags option in the test package.')
      ..addMultiOption('exclude-tags',
          abbr: 'x',
          help:
              'Select unit tests to exclude via their tags. The syntax must confirm to the --exclude-tags option in the test package.')
      ..addFlag(
        'show',
        abbr: 's',
        help: 'Also show output from successful unit tests.',
      )
      ..addFlag(
        'menu',
        abbr: 'm',
        help: 'Select from a menu of failed tests to view and re-run.',
      )
      ..addFlag(
        'progress',
        abbr: 'p',
        defaultsTo: true,
        help:
            'Show progress messages. Use --no-progress when running with a CI pipeline to minimize noise.',
      )
      ..addFlag(
        'coverage',
        defaultsTo: false,
        abbr: 'c',
        help: "Generates test coverage reports in the 'coverage' directory.",
      )
      ..addOption('log-path',
          abbr: 'g',
          help: 'Path to log all output. '
              'If set, all tests are logged to the given path.\n'
              'If not set, then all tests are logged to $defaultLogPath')
      ..addFlag(
        'hooks',
        abbr: 'o',
        defaultsTo: true,
        help: 'Supresses running of the pre and post hooks.',
      )
      ..addFlag(
        'warmup',
        abbr: 'w',
        defaultsTo: true,
        help: '''
Causes pub get to be run on all pubspec.yaml files found in the package.
Unit tests will fail if pub get hasn't been run.''',
      )
      ..addFlag(
        'track',
        abbr: 'k',
        defaultsTo: true,
        hide: true,
        help: 'Used to force the recording of failures in .failed_tracker.',
      )
      ..addOption(
        'tracker',
        defaultsTo: FailedTracker.defaultFilename,
        hide: true,
        help:
            'Used to define an alternate filename for the fail test tracker. This is intended only for internal testing',
      )
      ..addFlag(
        'verbose',
        negatable: false,
        abbr: 'v',
        hide: true,
        help: 'Verbose logging for debugging of critical test.',
      )
      ..addOption('settings-path', defaultsTo: Settings.defaultPath);
  }

  void parse(List<String> args) {
    try {
      parsed = parser.parse(args);
    } on FormatException catch (e) {
      printerr(red(e.message));
      printerr('');
      showUsage(parser);
    }

    if (parsed['help'] as bool == true) {
      showUsage(parser);
    }

    final pathToSettings = parsed['settings-path'] as String;

    var settings = Settings.loadFromPath(pathTo: pathToSettings);

    dcli.Settings().setVerbose(enabled: parsed['verbose'] as bool);

    showSuccess = getParsed(parsed, 'show', () => settings.show);
    menu = parsed['menu'] as bool;
    showProgress =
        getParsed(parsed, 'progress', () => settings.progress) || menu;

    coverage = getParsed(parsed, 'coverage', () => settings.coverage);
    warmup = getParsed(parsed, 'warmup', () => settings.warmup);
    track = getParsed(parsed, 'track', () => settings.track);
    hooks = getParsed(parsed, 'hooks', () => settings.hooks);
    runFailed = parsed['runfailed'] as bool;

    tags = getParsed(parsed, 'tags', () => settings.tags)
        .map((String t) => trimQuotes(t))
        .toList();
    excludeTags = getParsed(parsed, 'exclude-tags', () => settings.excludeTags)
        .map((String t) => trimQuotes(t))
        .toList();
    plainName =
        trimQuotes(getParsed(parsed, 'plain-name', () => settings.plainName));

    var hasFilter =
        tags.isNotEmpty || excludeTags.isNotEmpty || plainName.isNotEmpty;

    if (!atMostOne([
      menu,
      parsed.wasParsed('tags'),
      parsed.wasParsed('exclude-tags'),
      parsed.wasParsed('plain-name')
    ])) {
      printerr(red(
          'You may combine --menu with any of the filters [--plain-text, --tags, --exclude-tags]'));
      showUsage(parser);
    }

    if (!atMostOne([
      runFailed,
      parsed.wasParsed('tags'),
      parsed.wasParsed('exclude-tags'),
      parsed.wasParsed('plain-name')
    ])) {
      printerr(red(
          'You may combine --runFailed with any of the filters [--plain-text, --tags, --exclude-tags]'));
      showUsage(parser);
    }

    trackerFilename = parsed['tracker'] as String;

    if ((plainName.isNotEmpty) && (excludeTags.isNotEmpty || tags.isNotEmpty)) {
      printerr(red(
          'You cannot combine "--plain-name" with "--tags" or "--exclude-tags"'));
      showUsage(parser);
    }

    if (parsed.wasParsed('log-path')) {
      final _logPath = truepath(parsed['log-path'] as String);
      if (exists(_logPath) && !isFile(_logPath)) {
        printerr(red('--log-path must specify a file'));
        showUsage(parser);
      }
      logPath = _logPath;
    } else {
      logPath = settings.logPath;
    }

    pathToProjectRoot = DartProject.fromPath(pwd).pathToProjectRoot;
  }

  /// if [parsed] is enclosed in quotes then we strip them off.
  String trimQuotes(String parsed) {
    if (parsed.isEmpty) return parsed;
    final last = parsed.length - 1;
    if ((parsed[0] == "'" || parsed[0] == '"') &&
        (parsed[last] == "'" || parsed[last] == '"')) {
      return parsed.substring(1, last);
    }
    return parsed;
  }

  T getParsed<T>(ArgResults parsed, String name, T Function() defaultValue) {
    if (parsed.wasParsed(name)) {
      return parsed[name] as T;
    } else {
      return defaultValue();
    }
  }

  @override
  String toString() => 'test: $plainName args: ${parsed.arguments}';

  /// no more than one of the passed bools may be true
  bool atMostOne(List<bool> list) {
    var count = 0;

    for (final val in list) {
      if (val) count++;
    }
    return count <= 1;
  }
}

/// Show useage.
void showUsage(ArgParser parser) {
  print(orange('Usage: critical_test [switches] [<directory | library>...]'));
  print(
      'Runs unit tests only showing output from failed tests and allows you to just re-run failed tests.');
  print(blue(
      "Run all tests in the project 'test' directory if no directories or libraries a passed"));
  print('critical_test');
  print('');
  print(blue('Re-run failed tests'));
  print('critical_tests --runfailed');
  print('');
  print(blue('Run all tests in a Dart Library or directory'));
  print('critical_tests [<directory or library to test>]...');
  print('');
  print(blue('Run a single test by name'));
  print('critical_tests --plain-name="[<group name> ]... <test name>"');
  print('');
  print('''
tags, exclude-tags and plain-name all act as filters when running against 
selected directories or libraries and restrict the set of tests that are run.''');
  print(parser.usage);
  exit(1);
}
