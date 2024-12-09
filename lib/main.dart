import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: BluetoothPage(),
    );
  }
}

class BluetoothPage extends StatefulWidget {
  @override
  _BluetoothPageState createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothConnection? connection;
  bool isConnected = false;
  bool isConnecting = false;
  List<BluetoothDevice> pairedDevices = [];
  List<BluetoothDevice> availableDevices = [];
  BluetoothDevice? selectedDevice;

  String receivedData = ""; // To hold received message
  StreamSubscription<Uint8List>? _dataSubscription;
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySubscription;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    // Request Bluetooth permissions
    await _requestBluetoothPermissions();

    _bluetooth.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
      _getPairedDevices();
    });

    _bluetooth.onStateChanged().listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
      });
      _getPairedDevices();
    });
  }

  Future<void> _requestBluetoothPermissions() async {
    var status = await Permission.bluetoothScan.status;
    if (!status.isGranted) {
      await Permission.bluetoothScan.request();
    }
    status = await Permission.bluetoothConnect.status;
    if (!status.isGranted) {
      await Permission.bluetoothConnect.request();
    }
    status = await Permission.locationWhenInUse.status;
    if (!status.isGranted) {
      await Permission.locationWhenInUse.request();
    }
  }

  Future<void> _getPairedDevices() async {
    try {
      pairedDevices = await _bluetooth.getBondedDevices();
      setState(() {
        availableDevices =
            []; // Clear available devices before discovering new ones
      });
      _startDiscovery(); // Start discovering new devices
    } catch (e) {
      _showMessage('Error fetching paired devices');
    }
  }

  void _startDiscovery() {
    _discoverySubscription = FlutterBluetoothSerial.instance
        .startDiscovery()
        .listen((BluetoothDiscoveryResult result) {
      setState(() {
        if (!pairedDevices
            .any((device) => device.address == result.device.address)) {
          availableDevices.add(result.device);
        }
      });
    }, onDone: () {
      _discoverySubscription?.cancel();
    });
  }

  void _connect() async {
    if (selectedDevice != null) {
      setState(() {
        isConnecting = true;
      });

      try {
        connection =
            await BluetoothConnection.toAddress(selectedDevice!.address);
        setState(() {
          isConnected = true;
          isConnecting = false;
        });
        _showMessage('Connected to ${selectedDevice!.name}');
        _listenForData(); // Start listening for data immediately after connection
      } catch (e) {
        setState(() {
          isConnecting = false;
        });
        _showMessage('Failed to connect');
      }
    } else {
      _showMessage('No device selected');
    }
  }

  void _disconnect() {
    if (connection != null) {
      connection!.finish();
      _dataSubscription?.cancel();
      setState(() {
        isConnected = false;
      });
      _showMessage('Disconnected');
    }
  }

  void _sendMessage(Uint8List message) async {
    if (isConnected && connection != null) {
      connection!.output.add(message);
      await connection!.output.allSent;
      _showMessage('Message sent');

      // Start listening for data immediately after sending the command
      _listenForData();
    } else {
      _showMessage('Not connected to any device');
    }
  }

  // Listen for data from the Bluetooth device
  void _listenForData() {
    _dataSubscription = connection!.input!.listen((Uint8List data) {
      // Handle binary data (6 bytes)
      if (data.length == 6) {
        int maxVoltage = (data[0] << 8) | data[1]; // Max voltage (bytes 0,1)
        int maxCellCount = data[2]; // Max cell count (byte 2)
        int minVoltage = (data[3] << 8) | data[4]; // Min voltage (bytes 3,4)
        int minCellCount = data[5]; // Min cell count (byte 5)

        String message = 'Max Voltage: ${maxVoltage}mV\n'
            'Max Cell Count: $maxCellCount\n'
            'Min Voltage: ${minVoltage}mV\n'
            'Min Cell Count: $minCellCount';

        setState(() {
          receivedData += '$message\n';
        });

        _showMessage('Data received');
      } else {
        // _showMessage('Unexpected data length: ${data.length}');
      }
    }, onDone: () {
      _showMessage('Disconnected');
      setState(() {
        isConnected = false;
      });
    });
  }

  // Show snackbar messages
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth App'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
                'Bluetooth status: ${_bluetoothState.toString().split('.')[1]}',
                style: TextStyle(fontSize: 16)),
            ElevatedButton(
              onPressed: () async {
                if (_bluetoothState == BluetoothState.STATE_OFF) {
                  await _bluetooth.requestEnable();
                } else {
                  await _bluetooth.requestDisable();
                }
              },
              child: Text(_bluetoothState == BluetoothState.STATE_OFF
                  ? 'Enable Bluetooth'
                  : 'Disable Bluetooth'),
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<BluetoothDevice>(
              decoration: InputDecoration(
                labelText: 'Select a device',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.blue[50],
              ),
              value: selectedDevice,
              items: [
                ...pairedDevices.map((device) {
                  return DropdownMenuItem(
                    value: device,
                    child: Text(
                      device.name ?? 'Unknown',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }).toList(),
                ...availableDevices.map((device) {
                  return DropdownMenuItem(
                    value: device,
                    child: Text(
                      device.name ?? 'Unknown',
                      style: TextStyle(color: Colors.green),
                    ),
                  );
                }).toList(),
              ],
              onChanged: (device) {
                setState(() {
                  selectedDevice = device;
                });
              },
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: isConnecting ? null : _connect,
                  child: isConnecting ? Text('Connecting...') : Text('Connect'),
                ),
                ElevatedButton(
                  onPressed: isConnected ? _disconnect : null,
                  child: Text('Disconnect'),
                ),
              ],
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: isConnected
                  ? () => _sendMessage(Uint8List.fromList([0x91]))
                  : null,
              child: Text('Send 0x91'),
            ),
            Divider(),
            Text('Received Data:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                      receivedData.isEmpty ? 'No messages yet' : receivedData),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    connection?.dispose();
    _dataSubscription?.cancel();
    _discoverySubscription?.cancel();
    super.dispose();
  }
}






/*import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: BluetoothPage(),
    );
  }
}

class BluetoothPage extends StatefulWidget {
  @override
  _BluetoothPageState createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  BluetoothConnection? connection;
  bool isConnected = false;
  bool isConnecting = false;
  List<BluetoothDevice> pairedDevices = [];
  BluetoothDevice? selectedDevice;

  String receivedData = ""; // To hold received message
  StreamSubscription<Uint8List>? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    _bluetooth.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
      _getPairedDevices();
    });

    _bluetooth.onStateChanged().listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
      });
      _getPairedDevices();
    });
  }

  Future<void> _getPairedDevices() async {
    try {
      pairedDevices = await _bluetooth.getBondedDevices();
      setState(() {});
    } catch (e) {
      _showMessage('Error fetching paired devices');
    }
  }

  void _connect() async {
    if (selectedDevice != null) {
      setState(() {
        isConnecting = true;
      });

      try {
        connection =
            await BluetoothConnection.toAddress(selectedDevice!.address);
        setState(() {
          isConnected = true;
          isConnecting = false;
        });
        _showMessage('Connected to ${selectedDevice!.name}');
        _listenForData(); // Start listening for data immediately after connection
      } catch (e) {
        setState(() {
          isConnecting = false;
        });
        _showMessage('Failed to connect');
      }
    } else {
      _showMessage('No device selected');
    }
  }

  void _disconnect() {
    if (connection != null) {
      connection!.finish();
      _dataSubscription?.cancel();
      setState(() {
        isConnected = false;
      });
      _showMessage('Disconnected');
    }
  }

  void _sendMessage(Uint8List message) async {
    if (isConnected && connection != null) {
      connection!.output.add(message);
      await connection!.output.allSent;
      _showMessage('Message sent');

      // Start listening for data immediately after sending the command
      _listenForData();
    } else {
      _showMessage('Not connected to any device');
    }
  }

  // Listen for data from the Bluetooth device
  void _listenForData() {
    _dataSubscription = connection!.input!.listen((Uint8List data) {
      // Handle binary data (6 bytes)
      if (data.length == 6) {
        int maxVoltage = (data[0] << 8) | data[1]; // Max voltage (bytes 0,1)
        int maxCellCount = data[2]; // Max cell count (byte 2)
        int minVoltage = (data[3] << 8) | data[4]; // Min voltage (bytes 3,4)
        int minCellCount = data[5]; // Min cell count (byte 5)

        String message = 'Max Voltage: ${maxVoltage}mV\n'
            'Max Cell Count: $maxCellCount\n'
            'Min Voltage: ${minVoltage}mV\n'
            'Min Cell Count: $minCellCount';

        setState(() {
          receivedData += '$message\n';
        });

        _showMessage('Data received');
      } else {
        // _showMessage('Unexpected data length: ${data.length}');
      }
    }, onDone: () {
      _showMessage('Disconnected');
      setState(() {
        isConnected = false;
      });
    });
  }

  // Show snackbar messages
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth App'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
                'Bluetooth status: ${_bluetoothState.toString().split('.')[1]}',
                style: TextStyle(fontSize: 16)),
            ElevatedButton(
              onPressed: () async {
                if (_bluetoothState == BluetoothState.STATE_OFF) {
                  await _bluetooth.requestEnable();
                } else {
                  await _bluetooth.requestDisable();
                }
              },
              child: Text(_bluetoothState == BluetoothState.STATE_OFF
                  ? 'Enable Bluetooth'
                  : 'Disable Bluetooth'),
            ),
            SizedBox(height: 16),
            DropdownButtonFormField<BluetoothDevice>(
              decoration: InputDecoration(
                labelText: 'Select a device',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Colors.blue[50],
              ),
              value: selectedDevice,
              items: pairedDevices.map((device) {
                return DropdownMenuItem(
                  value: device,
                  child: Text(device.name ?? 'Unknown'),
                );
              }).toList(),
              onChanged: (device) {
                setState(() {
                  selectedDevice = device;
                });
              },
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: isConnecting ? null : _connect,
                  child: isConnecting ? Text('Connecting...') : Text('Connect'),
                ),
                ElevatedButton(
                  onPressed: isConnected ? _disconnect : null,
                  child: Text('Disconnect'),
                ),
              ],
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: isConnected
                  ? () => _sendMessage(Uint8List.fromList([0x91]))
                  : null,
              child: Text('Send 0x91'),
            ),
            Divider(),
            Text('Received Data:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: Text(
                      receivedData.isEmpty ? 'No messages yet' : receivedData),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    connection?.dispose();
    _dataSubscription?.cancel();
    super.dispose();
  }
}
*/