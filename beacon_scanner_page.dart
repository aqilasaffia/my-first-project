//beacon_scanner_page
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';

void fetchZoneFromFirebase(int? minor) async {
  if (minor == null) return;

  final ref = FirebaseDatabase.instance.ref('zones/$minor');

  final snapshot = await ref.get();

  if (snapshot.exists) {
    final zoneName = snapshot.child('name').value;
    print('Current zone: $zoneName');
  } else {
    print('Zone not found in Realtime Database');
  }
}

class BeaconScannerPage extends StatefulWidget {
  const BeaconScannerPage({super.key});

  @override
  _BeaconScannerPageState createState() => _BeaconScannerPageState();
}

class _BeaconScannerPageState extends State<BeaconScannerPage>
    with SingleTickerProviderStateMixin {
  String currentZone = "Unknown";
  String selectedDestination = "102";
  String instruction = "";

  final Map<String, Offset> beaconPositions = {
    "101": Offset(400, 50),
    "102": Offset(400, 230),
    "103": Offset(150, 400),
  };

  final Map<String, String> zoneNames = {
    "101": "Food Zone",
    "102": "Souvenir Zone",
    "103": "Jewellery Zone",
  };

  AnimationController? _controller;
  Animation<double>? _animation;
  final database = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    requestPermissions();
    startBLEScan();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0, end: 1).animate(_controller!);
  }

  @override
  void dispose() {
    _controller?.dispose();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> requestPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.location.request();
  }

  void startBLEScan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 6));

    FlutterBluePlus.scanResults.listen((results) {
      int maxRSSI = -999;
      String nearest = "";

      for (ScanResult r in results) {
        final manufacturerData = r.advertisementData.manufacturerData;

        if (manufacturerData.isNotEmpty) {
          final rawBytes = manufacturerData.values.first;
          final hex =
              rawBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
          print("🧬 Raw manufacturer data: $hex");

          if (rawBytes.length >= 25 &&
              rawBytes[0] == 0x02 &&
              rawBytes[1] == 0x15) {
            final major = (rawBytes[18] << 8) + rawBytes[19];
            final minor = (rawBytes[20] << 8) + rawBytes[21];
            print(
              "✅ Detected iBeacon -> Major: $major, Minor: $minor, RSSI: ${r.rssi}",
            );

            if (minor == 101 || minor == 102 || minor == 103) {
              if (r.rssi > maxRSSI) {
                maxRSSI = r.rssi;
                nearest = minor.toString();
              }
            }
          }
        }
      }

      print("➡️ Nearest beacon minor: $nearest (RSSI: $maxRSSI)");
      print("➡️ CurrentZone before update: $currentZone");

      if (nearest.isNotEmpty && nearest != currentZone) {
        setState(() {
          currentZone = nearest;
        });
        loadDirection();
      }
    });
  }

  void loadDirection() async {
    if (currentZone == "Unknown") return;

    final directionRef = database
        .child("zones")
        .child(currentZone)
        .child("direction_to")
        .child(selectedDestination);

    final snapshot = await directionRef.get();

    if (snapshot.exists) {
      setState(() {
        instruction = snapshot.value.toString();
      });
    } else {
      setState(() {
        instruction = "No direction available.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Offset? from = beaconPositions[currentZone];
    Offset? to = beaconPositions[selectedDestination];

    return Scaffold(
      appBar: AppBar(
        title: Text("Indoor Navigation"),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTapDown: (TapDownDetails details) {
                      final localPosition = details.localPosition;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            "Tapped: (${localPosition.dx.toStringAsFixed(0)}, ${localPosition.dy.toStringAsFixed(0)})",
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Image.asset(
                      "lib/assets/pasar_map.png",
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (from != null)
                  Positioned(
                    left: from.dx,
                    top: from.dy,
                    child: Icon(
                      Icons.person_pin_circle,
                      color: Colors.green,
                      size: 30,
                    ),
                  ),
                if (to != null)
                  Positioned(
                    left: to.dx,
                    top: to.dy,
                    child: Icon(Icons.flag, color: Colors.red, size: 30),
                  ),
                if (from != null && to != null)
                  AnimatedBuilder(
                    animation: _animation!,
                    builder: (context, child) {
                      Offset animPos = Offset(
                        lerpDouble(from.dx, to.dx, _animation!.value)!,
                        lerpDouble(from.dy, to.dy, _animation!.value)!,
                      );
                      return Positioned(
                        left: animPos.dx,
                        top: animPos.dy,
                        child: Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.blue,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                DropdownButton<String>(
                  value: selectedDestination,
                  items:
                      ["101", "102", "103"]
                          .map(
                            (e) => DropdownMenuItem(
                              child: Text("Go to ${zoneNames[e]}"),
                              value: e,
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedDestination = value!;
                      loadDirection();
                    });
                  },
                ),
                SizedBox(height: 10),
                Text("🧭 Current Zone: ${zoneNames[currentZone] ?? 'Unknown'}"),
                Text("🎯 Destination: ${zoneNames[selectedDestination]}"),
                SizedBox(height: 10),
                Text("📢 Direction: $instruction"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
