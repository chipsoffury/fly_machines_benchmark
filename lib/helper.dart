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

class FlyTestHelper {
  static final _log = Logger('FlyServerManager');
  static final _appName = 'cof-health-test';
  static final _image = 'cof-health-test';
  static final _version = '0.0.3';
  static final _baseApiUrl = 'https://$_appName.fly.dev';

  late final FlyMachinesRestClient flyMachinesRestClient;

  FlyTestHelper(String token) {
    flyMachinesRestClient = FlyMachinesRestClientProvider.get(token);
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
                interval: '10s',
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
      machineInfo = await flyMachinesRestClient.createMachine(
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
        await flyMachinesRestClient.waitForMachineStatus(
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
    var machineInfos = await flyMachinesRestClient.listMachines(_appName);
    while (machineInfos.isNotEmpty) {
      _log.info('Destroying ${machineInfos.length} machines...');
      try {
        await Future.wait(machineInfos.map((m) => flyMachinesRestClient.stopMachine(_appName, m.id)));
        await Future.delayed(Duration(seconds: 10));
        await Future.wait(machineInfos.map((m) => flyMachinesRestClient.destroyMachine(_appName, m.id)));
        await Future.delayed(Duration(seconds: 2));
      } catch (e) {
        // ignore
      }
      machineInfos = await flyMachinesRestClient.listMachines(_appName);
    }
  }

  Future<void> stopMachine(String machineId) async {
    await flyMachinesRestClient.stopMachine(_appName, machineId);
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
}
