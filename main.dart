   import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class AudioStreamingPage extends StatefulWidget {
  final String remoteOfferSdp;

  const AudioStreamingPage({Key? key, required this.remoteOfferSdp}) : super(key: key);

  @override
  _AudioStreamingPageState createState() => _AudioStreamingPageState();
}

class _AudioStreamingPageState extends State<AudioStreamingPage> {
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  FlutterSoundPlayer? _player;
  FlutterSoundRecorder? _recorder;

  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Set up peer connection
    final configuration = <String, dynamic>{
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    };
    _peerConnection = await createPeerConnection(configuration);

    // Set up data channel
    final channelInit = RTCDataChannelInit();
    _dataChannel = await _peerConnection!.createDataChannel('audio', channelInit);
    _dataChannel!.binaryType = 'arraybuffer';

    // Set up Flutter Sound player and recorder
    _player = await FlutterSoundPlayer().openAudioSession();
    _recorder = await FlutterSoundRecorder().openAudioSession();

    // Load audio file into memory as Uint8List
    final bytes = await rootBundle.load('assets/test.mp3');
    final buffer = bytes.buffer;
    final audioBytes = buffer.asUint8List();

    // Decode audio file using Flutter Sound
    final audioTrack = await _player!.startPlayerFromBuffer(audioBytes);

    // Add audio track to peer connection
    _peerConnection!.addTrack(audioTrack, [_peerConnection!.transceivers.first]);

    // Set up event listeners
    _dataChannel!.onDataChannelState = (state) {
      setState(() {
        _statusMessage = 'Data channel state changed to ${state.toString()}';
      });
    };
    _dataChannel!.onDataChannelMessage = (data) async {
      // Convert received data to Uint8List
      final bytes = Uint8List.fromList(data);

      // Play received audio data using Flutter Sound
      await _player!.feedFromStream(bytes);
    };

    // Set remote description from offer SDP
    final remoteOffer = RTCSessionDescription(
      widget.remoteOfferSdp,
      'offer',
    );
    await _peerConnection!.setRemoteDescription(remoteOffer);

    // Create answer and set local description
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    // Send answer to remote peer
    final answerSdp = _peerConnection!.localDescription!.toJson()['sdp'];
    _dataChannel!.send(answerSdp);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Audio Streaming')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_statusMessage.isNotEmpty) Text(_statusMessage),
         
    if (_localStream != null)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      // Start recording audio using Flutter Sound
                      await _recorder!.startRecorder(toFile: 'audio.mp3');
                    },
                    child: Text('Start Recording'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      // Stop recording audio
                      await _recorder!.stopRecorder();

                      // Get recorded audio data as Uint8List
                      final path = await _recorder!.getPath();
                      final bytes = await rootBundle.load(path);
                      final buffer = bytes.buffer;
                      final audioBytes = buffer.asUint8List();

                      // Send recorded audio data over data channel
                      _dataChannel!.send(audioBytes);
                    },
                    child: Text('Stop Recording'),
                  ),
                ],
              ),
            if (_remoteStream != null)
              Column(
                children: [
                  Text('Remote audio stream:'),
                  SizedBox(height: 16),
                  AudioElement(
                    RTCMediaStreamTrack(_remoteStream!.getAudioTracks()[0]),
                    autoPlay: true,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _player?.closeAudioSession();
    _recorder?.closeAudioSession();
    _peerConnection?.close();
    super.dispose();
  }
}