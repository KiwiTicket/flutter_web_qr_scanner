import 'dart:async';
import 'dart:html' hide VideoElement, MediaDevices;
import 'package:flutter/material.dart';
import 'package:tekartik_camera_web/media_devices.dart';
import 'package:tekartik_camera_web/media_devices_web.dart';
import 'package:tekartik_camera_web/video_element.dart';
import 'package:tekartik_camera_web/video_element_web.dart';
import 'package:tekartik_js_qr/js_qr.dart';
import 'package:tekartik_qrscan_flutter_web/src/view_registry.dart';

const _viewType = 'tekartik-qrscan-flutter-web-canvas';
final mediaDevices = mediaDevicesBrowser;

class ScanPage extends StatefulWidget {
  final String title;

  const ScanPage({Key key, this.title}) : super(key: key);

  @override
  _ScanPageState createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  var scaffoldKey = GlobalKey<ScaffoldState>();

  // Auto play needed for Chrome
  VideoElement videoElement;
  Widget _webcamWidget;
  MediaStream mediaStream;
  String viewType;
  CanvasElement canvasElement;
  CanvasRenderingContext2D canvas;
  static var _id = 0;
  double _aspectRatio;
  Timer _timeoutTimer;

  @override
  void dispose() {
    mediaStream?.getTracks()?.forEach((element) {
      element.stop();
    });
    videoElement?.pause();
    videoElement?.src = null;
    videoElement?.remove();
    _validateTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _initCanvas() {
    if (canvas == null || canvasElement == null) {
      try {
        canvasElement = CanvasElement(
          width: videoElement.videoWidth,
          height: videoElement.videoHeight,
        );
        canvas = canvasElement.getContext('2d') as CanvasRenderingContext2D;

        registerViewFactoryWeb(viewType, (int viewId) {
          return canvasElement;
        });

        _aspectRatio = videoElement.videoWidth / videoElement.videoHeight;
        _webcamWidget = HtmlElementView(key: viewKey, viewType: viewType);
      } catch (e) {
        // scaffoldKey.currentState.showSnackBar(SnackBar(
        //   content: Text('Having trouble displaying the camera: $e'),
        // ));
      }

      // refresh the UI
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();

    _timeoutTimer = Timer(Duration(seconds: 30), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });

    viewType = '$_viewType-${++_id}';
    viewKey = UniqueKey();
    videoElement = VideoElementWeb();

    // Needed for iOS safari
    videoElement.allowPlayInline();

    WidgetsBinding.instance.addPostFrameCallback((_) => afterFirstLayout());
  }

  Future afterFirstLayout() async {
    // Again, just in case... Safari iOS
    videoElement.allowPlayInline();

    try {
      var stream = mediaStream = await mediaDevices.getUserMedia(
        GetUserMediaConstraint(
          video: GetUserMediaVideoConstraint(
            facingMode: mediaVideoConstraintFacingModeEnvironment,
          ),
        ),
      );

      videoElement.srcObject = stream;
      await videoElement.play();
      await _tick();
    } catch (e) {
      // scaffoldKey.currentState.showSnackBar(SnackBar(
      //   content: Text('Couldn\'t start camera: $e'),
      // ));
    }
  }

  Future _tick() async {
    while (mounted) {
      try {
        await window.animationFrame;

        if (videoElement.hasEnoughData) {
          _initCanvas();

          canvasElement.height = videoElement.videoHeight;
          canvasElement.width = videoElement.videoWidth;
          canvas.drawImage(
              (videoElement as VideoElementWeb).nativeVideoElement, 0, 0);

          var imageData = canvas.getImageData(
              0, 0, canvasElement.width, canvasElement.height);
          var qrCode = decodeQrCode(
            imageData: imageData.data,
            width: canvasElement.width,
            height: canvasElement.height,
          );

          if (qrCode != null) {
            var color = '#FF3B58';
            void drawLine(QrCodePoint begin, QrCodePoint end) {
              canvas.beginPath();
              canvas.moveTo(begin.x, begin.y);
              canvas.lineTo(end.x, end.y);
              canvas.lineWidth = 4;
              canvas.strokeStyle = color;
              canvas.stroke();
            }

            drawLine(qrCode.location.topLeft, qrCode.location.topRight);
            drawLine(qrCode.location.topRight, qrCode.location.bottomRight);
            drawLine(qrCode.location.bottomRight, qrCode.location.bottomLeft);
            drawLine(qrCode.location.bottomLeft, qrCode.location.topLeft);

            _validateQrCodeData(qrCode.data);
          }
        }
      } catch (e) {
        // scaffoldKey.currentState.showSnackBar(SnackBar(
        //   content: Text('Having issues capturing from camera'),
        // ));
      }
    }
  }

  Timer _validateTimer;

  String _lastQrCodeData;
  void _validateQrCodeData(String data) {
    if (data != _lastQrCodeData) {
      _lastQrCodeData = data;

      _validateTimer?.cancel();
      _validateTimer = Timer(
        Duration(milliseconds: 800),
        () {
          if (mounted) {
            Navigator.of(context).pop(data);
          }
        },
      );
    }
  }

  UniqueKey viewKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      appBar: widget.title != null
          ? AppBar(
              title: Text(widget.title),
            )
          : null,
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Container(
                    color: Colors.black,
                    child: _webcamWidget != null
                        ? Align(
                            alignment: Alignment.center,
                            child: AspectRatio(
                              aspectRatio: _aspectRatio,
                              child: _webcamWidget,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
