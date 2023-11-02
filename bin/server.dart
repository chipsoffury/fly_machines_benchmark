import 'dart:io';

import 'package:fly_health_test/shelf_response.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

Future<void> main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  final log = Logger('health-test-server');

  var router = Router();

  router.get('/health', (request) async {
    log.info('health check responding');
    return ShelfResponse.ok({'status': 'ok'});
  });

  router.get('/hello', (request) {
    log.fine('sending hello world');
    return ShelfResponse.ok({'hello': 'world'});
  });

  router.get('/stop', (request) {
    log.warning('stopping admin server');
    exit(0);
  });

  router.get('/crash', (request) {
    log.severe('crashing admin server');
    exit(1);
  });

  // catch all route
  router.get('/<catch|.*>', (request) {
    return ShelfResponse.forbidden('bad request path');
  });

  var server = await io.serve(router, '0.0.0.0', 8080);
  log.info('server running at ${server.address.host}:${server.port}');
}
