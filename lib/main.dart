import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:flutter/services.dart';

void main() {
  runApp(MyApp());
}


class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth Car Status',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Home(),
    );
  }
}

class Home extends StatefulWidget {
  @override
  _HomeState createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool _isBluetoothEnabled = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndBluetooth();
  }

  Future<void> _checkPermissionsAndBluetooth() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();

    if (statuses[Permission.location]!.isGranted &&
        statuses[Permission.bluetooth]!.isGranted &&
        statuses[Permission.bluetoothConnect]!.isGranted &&
        statuses[Permission.bluetoothScan]!.isGranted) {
      bool? isBluetoothEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (!isBluetoothEnabled!) {
        isBluetoothEnabled = await FlutterBluetoothSerial.instance.requestEnable();
      }

      setState(() {
        _isBluetoothEnabled = isBluetoothEnabled!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Devices'),
      ),
      body: _isBluetoothEnabled
          ? SelectBondedDevicePage(
        onDeviceSelected: (device) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) {
                return StatusPage(server: device);
              },
            ),
          );
        },
      )
          : Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled,
              size: 200.0,
              color: Colors.blue,
            ),
            SizedBox(height: 20),
            Text('Enable Bluetooth to see devices'),
          ],
        ),
      ),
    );
  }
}

class SelectBondedDevicePage extends StatefulWidget {
  final Function(BluetoothDevice) onDeviceSelected;

  const SelectBondedDevicePage({required this.onDeviceSelected});

  @override
  _SelectBondedDevicePageState createState() => _SelectBondedDevicePageState();
}

class _SelectBondedDevicePageState extends State<SelectBondedDevicePage> {
  List<BluetoothDevice> devices = [];
  bool _isDiscovering = true;

  @override
  void initState() {
    super.initState();
    _getBondedDevices();
  }

  Future<void> _getBondedDevices() async {
    try {
      devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        _isDiscovering = false;
      });
      if (devices.isEmpty) {
        print("No bonded devices found.");
      } else {
        print("Bonded devices found: ${devices.length}");
      }
    } catch (e) {
      print("Error fetching bonded devices: $e");
      setState(() {
        _isDiscovering = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isDiscovering
        ? Center(child: CircularProgressIndicator())
        : devices.isEmpty
        ? Center(child: Text('No devices found'))
        : ListView(
      children: devices
          .map(
            (device) => ListTile(
          title: Text(device.name ?? "Unknown Device"),
          subtitle: Text(device.address.toString()),
          trailing: IconButton(
            icon: Icon(Icons.bluetooth_connected),
            onPressed: () {
              widget.onDeviceSelected(device);
            },
          ),
        ),
      )
          .toList(),
    );
  }
}

class StatusPage extends StatefulWidget {
  final BluetoothDevice server;

  const StatusPage({required this.server});

  @override
  _StatusPageState createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  late BluetoothConnection connection;
  bool isConnecting = true;
  bool isConnected = false;
  String carStatus = "Unknown";
  String motionStatus = "Unknown";
  String rawData = "No data received";  // Add a raw data string
  String cameraUrl = 'http://192.168.39.138/cam-hi.jpg'; // Your camera URL
  late Timer _cameraTimer;
  late Future<http.Response> _cameraImageFuture;
  late Future<http.Response> _detectionResponse;

  String _buffer = ""; // Accumulate incoming data in this buffer

  @override
  void initState() {
    super.initState();
    _connectToDevice();
    _cameraImageFuture = _fetchCameraImage();
    _cameraTimer = Timer.periodic(Duration(seconds: 1), (Timer t) {
      setState(() {
        _cameraImageFuture = _fetchCameraImage();
      });
    });
  }

  Future<void> _connectToDevice() async {
    setState(() {
      isConnecting = true;
    });

    try {
      connection = await BluetoothConnection.toAddress(widget.server.address);
      setState(() {
        isConnecting = false;
        isConnected = true;
      });

      connection.input?.listen((data) {
        // Append incoming data to buffer
        _buffer += String.fromCharCodes(data);

        // Process the buffer when a newline (or another delimiter) is detected
        if (_buffer.contains('\n')) {
          List<String> messages = _buffer.split('\n');

          // Process all complete messages
          for (var message in messages) {
            if (message.isNotEmpty) {
              setState(() {
                rawData = message.trim();  // Display the raw data

                // Here you could parse the message and update car/motion status
                // For example, if the message contains "CarStatus" and "MotionStatus"
                if (message.contains("CarStatus")) {
                  carStatus = message.split(",")[0].split(":")[1].trim();
                }
                if (message.contains("MotionStatus")) {
                  motionStatus = message.split(",")[1].split(":")[1].trim();
                }
              });

              print("Processed message: $message");

              // Trigger image detection if needed
              if (carStatus == "At Home") {
                _fetchCameraImage().then((imageResponse) {
                  // Send image to Flask server for detection
                  _sendImageForDetection(imageResponse.bodyBytes);
                });
              }
            }
          }

          // Clear the buffer after processing the complete messages
          _buffer = messages.last;
        }
      }).onDone(() {
        setState(() {
          isConnected = false;
        });
      });
    } catch (e) {
      print('Cannot connect, exception occurred: $e');
      setState(() {
        isConnecting = false;
        isConnected = false;
      });
    }
  }

  Future<http.Response> _fetchCameraImage() async {
    return await http.get(Uri.parse(cameraUrl));
  }

  Future<void> _sendImageForDetection(Uint8List imageBytes) async {
    final uri = Uri.parse('http://192.168.39.217:5000/detect');
    final request = http.MultipartRequest('POST', uri)
      ..files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: 'image.jpg'));

    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        final responseBody = await response.stream.bytesToString();
        print('Response: $responseBody');
      } else {
        print('Failed to send image. Status code: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending image: $e');
    }
  }

  @override
  void dispose() {
    _cameraTimer.cancel();
    connection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Car Status & Camera Feed', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: isConnecting
              ? CircularProgressIndicator()
              : isConnected
              ? Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(height: 10),
              _buildStatusCard('Car Status', carStatus),
              SizedBox(height: 10),
              _buildStatusCard('Motion Status', motionStatus),
              SizedBox(height: 20),
              Text('Live Camera Feed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              _buildCameraFeed(),
            ],
          )
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Disconnected', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _connectToDevice,
                child: Text('Connect'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  textStyle: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(String title, String status) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              status,
              style: TextStyle(fontSize: 18, color: Colors.blueAccent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraFeed() {
    return FutureBuilder<http.Response>(
      future: _cameraImageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        } else if (snapshot.hasError) {
          return Text('Error loading camera feed');
        } else {
          final bytes = snapshot.data!.bodyBytes;
          return Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(bytes, fit: BoxFit.cover),
            ),
          );
        }
      },
    );
  }
}
