import 'dart:async';
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
      title: 'OzoTec Bluetooth App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
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

  String receivedData = ""; // hold the received message
  StreamSubscription<Uint8List>? _dataSubscription;

  @override
  void initState() {
    super.initState();
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
        _listenForData();//receiving data ready
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

  void _sendMessage(String message) async {
    if (isConnected && connection != null) {
      connection!.output.add(Uint8List.fromList(message.codeUnits));
      await connection!.output.allSent;
      _showMessage('Message sent: $message');
    } else {
      _showMessage('Not connected to any device');
    }
  }

  // Listen for data from the Bluetooth device
  void _listenForData() {
    _dataSubscription = connection!.input!.listen((Uint8List data) {
      String message = String.fromCharCodes(data);
      setState(() {
        receivedData += message; // Update the received message
      });
      _showMessage('Message received: $message');
    }, onDone: () {
      _showMessage('Disconnected');
      setState(() {
        isConnected = false;
      });
    });
  }

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
        padding: const EdgeInsets.all(2.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
                'Bluetooth status: ${_bluetoothState.toString().split('.')[1]}'),
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
            if (!isConnected)
              ElevatedButton(
                onPressed: isConnecting ? null : _connect,
                child: isConnecting ? Text('Connecting...') : Text('Connect'),
              ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: isConnected ? _disconnect : null,
              child: Text('Disconnect'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: isConnected ? () => _sendMessage('1') : null,
              child: Text('Turn On (Send 1)'),
            ),
            ElevatedButton(
              onPressed: isConnected ? () => _sendMessage('0') : null,
              child: Text('Turn Off (Send 0)'),
            ),
            Divider(),
            Text('Received Messages:'),
            Expanded(
              child: Container(
                width: MediaQuery.of(context).size.width,
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent),
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