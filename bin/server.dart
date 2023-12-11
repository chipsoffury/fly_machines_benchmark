import 'dart:async';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:fly_health_test/shelf_response.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

final log = Logger('health-test-server');

final int IDLE_TO_STOP_SECONDS_DEFAULT = 60;

Timer createIdleToShutdownTimer(int seconds) {
  return Timer(Duration(seconds: seconds != 0 ? seconds : IDLE_TO_STOP_SECONDS_DEFAULT), () async {
    log.info('shutting down after $seconds seconds of idle');
    exit(0);
  });
}

Future<void> main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  var env = DotEnv(includePlatformEnvironment: true)..load();

  var idleToShutdownSeconds = int.parse(env['IDLE_TO_STOP_SECONDS'] ?? '0');
  var idleToShutdownTimer = createIdleToShutdownTimer(idleToShutdownSeconds);

  var router = Router();

  router.get('/health', (request) async {
    log.info('health check responding');
    idleToShutdownTimer.cancel();
    idleToShutdownTimer = createIdleToShutdownTimer(idleToShutdownSeconds);
    return ShelfResponse.ok({'status': 'ok'});
  });

  router.get('/hello', (request) {
    log.fine('sending hello world');
    idleToShutdownTimer.cancel();
    idleToShutdownTimer = createIdleToShutdownTimer(idleToShutdownSeconds);
    return ShelfResponse.ok({'hello': 'world'});
  });

  router.get('/stop', (request) {
    log.warning('stopping admin server');
    idleToShutdownTimer.cancel();
    idleToShutdownTimer = createIdleToShutdownTimer(idleToShutdownSeconds);
    exit(0);
  });

  router.get('/crash', (request) {
    log.severe('crashing admin server');
    idleToShutdownTimer.cancel();
    idleToShutdownTimer = createIdleToShutdownTimer(idleToShutdownSeconds);
    exit(1);
  });

  router.get('/<catch|.*>', (request) {
    idleToShutdownTimer.cancel();
    idleToShutdownTimer = createIdleToShutdownTimer(idleToShutdownSeconds);
    return ShelfResponse.forbidden('bad request path');
  });

  var server = await io.serve(router, '0.0.0.0', 8080);
  log.info('server running at ${server.address.host}:${server.port}');
}
