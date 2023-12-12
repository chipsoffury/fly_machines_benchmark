import 'package:fly_io_client/fly_constants.dart';
import 'package:fly_io_client/fly_machine_status.dart';
import 'package:fly_io_client/request/create_machine_request.dart';
import 'package:fly_io_client/response/machine_info_response.dart';
import 'package:fly_io_client/rest_client/fly_machines_rest_client.dart';
import 'package:logging/logging.dart';

import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

const _uuidGen = Uuid();

class DataEntry {
  final String id;
  final FlyRegion region;
  final int createdAt;
  final int timeToStart;
  final int timeToRespond;

  DataEntry({required this.id, required this.region, required this.createdAt, required this.timeToStart, required this.timeToRespond});
}

bool canBeStopped(FlyMachineStatus status) {
  return status != FlyMachineStatus.destroying &&
      status != FlyMachineStatus.destroyed &&
      status != FlyMachineStatus.starting &&
      status != FlyMachineStatus.replacing &&
      status != FlyMachineStatus.failed &&
      status != FlyMachineStatus.created &&
      status != FlyMachineStatus.unknown;
}

class FlyTestHelper {
  static final _log = Logger('FlyServerManager');

  late final FlyMachinesRestClient _flyMachinesRestClient;

  late final String _appName;
  late final String _image;
  late final String _version;
  late final String _baseApiUrl;
  late final int _idleToStop;

  FlyTestHelper(
    String token, {
    String? appName,
    String? image,
    String? version,
    int? idleToStop,
  }) {
    _flyMachinesRestClient = FlyMachinesRestClient(token);
    _appName = appName ?? 'cof-health-test';
    _image = image ?? 'cof-health-test';
    _version = version ?? '0.0.3';
    _idleToStop = idleToStop ?? 0;
    _baseApiUrl = 'https://$_appName.fly.dev';
  }

  Future<MachineInfoResponse> createMachine(FlyRegion flyRegion) async {
    var serverId = _uuidGen.v4();
    var machineName = '$_appName-$serverId';
    var port = 8080;

    var createMachineRequest = CreateMachineRequest(
      machineName,
      MachineConfig(
        image: 'registry.fly.io/$_image:v$_version',
        size: MachineSize.shared_cpu_2x,
        env: {
          'SERVERS': 'test',
          'TEST_SERVER_PORT': port.toString(),
          'IDLE_TO_STOP_SECONDS': _idleToStop.toString(),
        },
        services: [
          MachineService(
            ServiceProtocol.tcp,
            port,
            [
              MachineServicePort(
                443,
                [MachineServiceConnectionHandler.tls, MachineServiceConnectionHandler.http],
              ),
            ],
            concurrency: MachineServiceConcurrency(MachineServiceConcurrencyType.connections, 50, 100),
            checks: [
              MachineCheck(
                grace_period: '0s',
                interval: '${_idleToStop != 0 ? (_idleToStop + 10).toString() : '10'}s',
                timeout: '2s',
                method: 'get',
                path: '/health',
                protocol: 'http',
                type: MachineCheckType.http,
                port: port,
              ),
            ],
          ),
        ],
      ),
      region: flyRegion,
    );

    MachineInfoResponse machineInfo;
    try {
      _log.info('Issuing a request to create $machineName in ${flyRegion.code}');
      machineInfo = await _flyMachinesRestClient.createMachine(
        _appName,
        createMachineRequest,
      );
    } catch (e) {
      _log.severe('Error creating a machine: $e');
      rethrow;
    }

    _log.info('Machine $machineName (${machineInfo.id}) created successfully');
    return machineInfo;
  }

  Future<int> waitForMachineToStart(String machineId, {int timeout = 60}) async {
    assert(timeout <= 60);

    _log.info('Waiting for machine with id $machineId to start...');

    var t1 = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      try {
        await _flyMachinesRestClient.waitForMachineStatus(
          _appName,
          machineId,
          FlyMachineStatus.started,
          timeoutSeconds: timeout,
        );
        var t2 = DateTime.now().millisecondsSinceEpoch;
        _log.info('Machine $machineId started in ${t2 - t1} milliseconds');

        return t2 - t1;
      } catch (e) {
        // ignore
      }
    }
  }

  Future<int> waitForMachineToBecomeHealthy(String machineId) async {
    _log.info('Waiting for machine with id $machineId to become responsive...');

    var url = Uri.parse('$_baseApiUrl/health');
    var t1 = DateTime.now().millisecondsSinceEpoch;
    while (true) {
      try {
        await http.get(url, headers: {
          'fly-force-instance-id': machineId,
        }).timeout(Duration(seconds: 1), onTimeout: () async {
          await Future.delayed(Duration(seconds: 1));
          throw Exception('Timeout waiting for machine $machineId to become responsive');
        });
        var t2 = DateTime.now().millisecondsSinceEpoch;
        _log.info('Machine $machineId became responsive in ${t2 - t1} milliseconds');
        return t2 - t1;
      } catch (e) {
        // ignore
      }
    }
  }

  Future<void> stopAndDestroyAllMachines() async {
    var machines = await _flyMachinesRestClient.listMachines(_appName);
    var startedMachines = machines.where((m) => canBeStopped(FlyMachineStatus.fromString(m.state) ?? FlyMachineStatus.unknown)).toList();
    while (startedMachines.isNotEmpty) {
      _log.info('Destroying ${startedMachines.length} machines...');
      try {
        await Future.wait(startedMachines.map((m) => _flyMachinesRestClient.stopMachine(_appName, m.id)));
        await Future.delayed(Duration(seconds: 10));
        await Future.wait(startedMachines.map((m) => _flyMachinesRestClient.destroyMachine(_appName, m.id)));
        await Future.delayed(Duration(seconds: 2));
      } catch (e) {
        // ignore
      }
      startedMachines = (await _flyMachinesRestClient.listMachines(_appName))
          .where((m) => canBeStopped(FlyMachineStatus.fromString(m.state) ?? FlyMachineStatus.unknown))
          .toList();
    }
  }

  Future<void> stopMachine(String machineId) async {
    await _flyMachinesRestClient.stopMachine(_appName, machineId);
  }

  Future<DataEntry> testForCreationAndResponse(FlyRegion region, {int creationTimeout = 60}) async {
    try {
      var machineInfo = await createMachine(region);
      var tts = await waitForMachineToStart(machineInfo.id, timeout: creationTimeout);
      var ttr = await waitForMachineToBecomeHealthy(machineInfo.id);
      return DataEntry(id: machineInfo.id, region: region, createdAt: machineInfo.created_at, timeToStart: tts, timeToRespond: ttr);
    } catch (e) {
      _log.severe('Error creating and testing machine: $e');
      rethrow;
    }
  }

  Future<DataEntry> testForColdResponse(FlyRegion region, {int creationTimeout = 60}) async {
    try {
      var machineInfo = await createMachine(region);
      var tts = await waitForMachineToStart(machineInfo.id, timeout: creationTimeout);
      var _ = await waitForMachineToBecomeHealthy(machineInfo.id);
      var ttr = await Future.delayed(Duration(seconds: _idleToStop + 10), () => waitForMachineToBecomeHealthy(machineInfo.id));
      return DataEntry(id: machineInfo.id, region: region, createdAt: machineInfo.created_at, timeToStart: tts, timeToRespond: ttr);
    } catch (e) {
      _log.severe('Error creating and testing machine: $e');
      rethrow;
    }
  }
}
