import 'dart:io';

import 'package:csv/csv.dart';
import 'package:dotenv/dotenv.dart';
import 'package:fly_health_test/helper.dart';
import 'package:fly_io_client/fly_constants.dart';
import 'package:logging/logging.dart';

void main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  var env = DotEnv(includePlatformEnvironment: true)..load();
  var flyTestHelper = FlyTestHelper(
    env['FLY_AUTH_TOKEN']!,
    appName: env['FLY_APP_NAME'],
    image: env['FLY_IMAGE'],
    version: env['FLY_VERSION'],
  );

  await flyTestHelper.stopAndDestroyAllMachines();

  // ignore: prefer_is_empty
  var n = args.length > 0 ? int.parse(args[0]) : 1;
  var region = args.length > 1 ? FlyRegion.fromCode(args[1]) : FlyRegion.sin;
  var t = args.length > 2 ? int.parse(args[2]) : 60;

  var results = <List<dynamic>>[];

  var resultsStream =
      Stream.fromFutures(Iterable.generate(n).map((_) => flyTestHelper.testForColdResponse(region, creationTimeout: t)));

  await for (final entry in resultsStream) {
    results.add([entry.id, entry.region.code, entry.createdAt, entry.timeToStart, entry.timeToRespond]);
  }

  var fileName = 'results-cold-${region.code}.csv';
  var file = File(fileName);

  if (!(await file.exists())) {
    results.insert(0, ['Machine id', 'Region', 'Created at', 'Time to start', 'Time to respond (cold start)']);
  }

  var resultsAsCSV = const ListToCsvConverter().convert(results);
  resultsAsCSV += '\r\n';
  var fileSink = file.openWrite(mode: FileMode.append);
  fileSink.write(resultsAsCSV);

  await flyTestHelper.stopAndDestroyAllMachines();

  exit(0);
}
