import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:signalr_client/signalr_client.dart';
import 'package:logging/logging.dart';
import 'package:webrtc_signalr/signaling.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

MediaStream stram;
Signaling signal = new Signaling();
String partnerId;
RTCPeerConnection connection;
IUser user;
UserConnection userConnection;
HubConnection _hubConnection;
String currentConnectionId;
String currentRoomName = "Test1";
MediaStream currentMediaStream;
bool connected = false;
Map<String, UserConnection> _connections = new Map<String, UserConnection>();
bool _inCalling = false;
RTCVideoRenderer _localRenderer = new RTCVideoRenderer();
RTCVideoRenderer _remoteRenderer = new RTCVideoRenderer();

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  @override
  void initState() {
    sleep(Duration(seconds: 2));
    initRenderers();
    _connect();
    super.initState();
  }

  initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return new Scaffold(
      appBar: new AppBar(
        title: new Text('P2P Call Sample'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: null,
            tooltip: 'setup',
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _inCalling
          ? new SizedBox(
              width: 200.0,
              child: new Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    FloatingActionButton(
                      child: const Icon(Icons.switch_camera),
                      onPressed: null,
                    ),
                    FloatingActionButton(
                      onPressed: null,
                      tooltip: 'Hangup',
                      child: new Icon(Icons.call_end),
                      backgroundColor: Colors.pink,
                    ),
                    FloatingActionButton(
                      child: const Icon(Icons.mic_off),
                      onPressed: null,
                    )
                  ]))
          : null,
      body: _inCalling
          ? OrientationBuilder(builder: (context, orientation) {
              return new Container(
                child: new Stack(children: <Widget>[
                  new Positioned(
                      left: 0.0,
                      right: 0.0,
                      top: 0.0,
                      bottom: 0.0,
                      child: new Container(
                        margin: new EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        child: new RTCVideoView(_remoteRenderer),
                        decoration: new BoxDecoration(color: Colors.black54),
                      )),
                  new Positioned(
                    left: 20.0,
                    top: 20.0,
                    child: new Container(
                      width: orientation == Orientation.portrait ? 90.0 : 120.0,
                      height:
                          orientation == Orientation.portrait ? 120.0 : 90.0,
                      child: new RTCVideoView(_localRenderer),
                      decoration: new BoxDecoration(color: Colors.black54),
                    ),
                  ),
                ]),
              );
            })
          : new ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: (_connections != null ? _connections.length : 0),
              itemBuilder: (context, i) {
                return Container();
                // return _buildRow(context, _peers[i]);
              }),
    );
  }
}

Map<String, dynamic> configuration = {
  "iceServers": [
    {"url": "stun:stun.l.google.com:19302"},
  ]
};

final Map<String, dynamic> constraints = {
  "mandatory": {},
  "optional": [
    {"DtlsSrtpKeyAgreement": true},
  ],
  "partnerId": ""
};

_connect() async {
  // The location of the SignalR Server.
  final serverUrl = "https://0f145986.ngrok.io/sgr/rtc";

  Logger.root.level = Level.WARNING;

  Logger.root.onRecord.listen((LogRecord rec) {
    print('${rec.level.name}: ${rec.time}: ${rec.message}');
  });

  final hubProtLogger = Logger("SignalR - hub");

  var httpOptions = new HttpConnectionOptions(logger: hubProtLogger);
// Creates the connection by using the HubConnectionBuilder.
  _hubConnection =
      HubConnectionBuilder().withUrl(serverUrl, options: httpOptions).build();

  await _hubConnection.start();
// When the connection is closed, print out a message to the console.
  _hubConnection
      .onclose((error) => print("Connection Closed " + error.toString()));

  if (_hubConnection.state == HubConnectionState.Connected) {
    currentConnectionId = await _hubConnection.invoke('GetConnectionId');
    connected = true;
    _closeAllVideoCalls();
    _hubConnection.on('callToUserList', _callToUserList);
    _hubConnection.on('updateUserList', _updateUserList);

    _hubConnection.on('receiveSignal', _signalReceived);

    // TO DO

    var user = IUser('', currentConnectionId);
    _connections[currentConnectionId] = new UserConnection(user, true, null);
    currentRoomName = 'Test1';
    _hubConnection.invoke('Join', args: <Object>["mobile2", "Test1"]);
  } else
    return;
}

Future<void> _initiateOffer(IUser acceptingUser) async {
  print('Initiate offer to ' + acceptingUser.connectionId);
  var connection = await getConnection(acceptingUser.connectionId);
  var stream = await signal.createStream('video', false);
  stream
      .getVideoTracks()
      .forEach((track) => {connection.rtcConnection.addStream(stream)});
}

Future<UserConnection> getConnection(String connectionId) async {
  if (_connections[connectionId] != null) {
    return _connections[connectionId];
  } else {
    return await createConnection(connectionId);
  }
}

Future<List<dynamic>> getIceServers() async {
  var results = await _hubConnection.invoke('GetIceServers') as List;
  return results;
}

Future<UserConnection> createConnection(String partnerClientId) async {
  print('WebRTC: creating connection...');

  if (_connections[partnerClientId] != null) {
    // this.closeVideoCall(partnerClientId);
  }

  constraints["partnerId"] = partnerClientId;
  partnerId = partnerClientId;
  connection = await createPeerConnection(configuration, constraints);
  user = new IUser('', partnerClientId);
  userConnection = new UserConnection(user, false, connection);

  connection.onRenegotiationNeeded = _onRenegotiationNeeded;
  connection.onIceConnectionState = _iceConnectionStateChanged;
  connection.onIceGatheringState = _iceGatheringState;
  connection.onSignalingState = _signalingState;
  connection.onIceCandidate = _onIceCandidate;
  connection.onAddTrack = _onAddTrack;

  // var desc = await connection.createOffer(constraints);
  // connection.setLocalDescription(desc);
  // var d = await connection.getLocalDescription();
  // _sendSignal(new ISignal(SignalType.videoAnswer, d), partnerClientId);
  _connections[partnerClientId] = userConnection;

  return userConnection;
}

_onAddTrack(MediaStream stream, MediaStreamTrack track) {
  print('Track received from ' + user.connectionId);
  userConnection.setStream(stream);
}

_onIceCandidate(RTCIceCandidate candidate) {
  print(jsonEncode(candidate));
  if (candidate != null) {
    print("WebRTC : new ICE candidate !");
    _sendSignal(
        new ISignal(type: SignalType.newIceCandidate, candidate: candidate),
        partnerId);
  }
}

_signalingState(RTCSignalingState state) {
  print("**** WebRTC signaling state changed to : " + state.toString());
}

_iceGatheringState(RTCIceGatheringState state) {
  print('RTCIceGatheringState = ' + state.toString());
}

_onRenegotiationNeeded() async {
  if (userConnection.creatingOffer) {
    return;
  } else {
    userConnection.creatingOffer = true;
    var desc = await connection.createOffer(constraints);
    await connection.setLocalDescription(desc);
    await _sendSignal(
        new ISignal(type: SignalType.videoOffer, sdp: desc), partnerId);
  }

  userConnection.creatingOffer = false;
}

_iceConnectionStateChanged(RTCIceConnectionState state) {
  switch (state) {
    case RTCIceConnectionState.RTCIceConnectionStateClosed:
      {
        print('RTC State Closed');
        break;
      }
    case RTCIceConnectionState.RTCIceConnectionStateConnected:
      {
        print('RTC State Connected');

        break;
      }
    case RTCIceConnectionState.RTCIceConnectionStateFailed:
      {
        print('RTC State Failed');

        break;
      }
    default:
      {
        break;
      }
  }
}

_sendSignal(ISignal signal, String partnerClientId) async {
  try {
    var e = signal.toJson();
    var s = jsonEncode(e);
    if(e['sdp'] == null || e['sdp'] == ''){
      e['sdp'] = "''";
    }
    else if(e['candidate'] == null || e['candidate'] == ''){
      e['candidate'] = "''";
    }
    print(e);
    //  print('SIGNAL TO JSON ->>>>>' + p);
    await _hubConnection
        .invoke('SendSignal', args: <Object>[s, partnerClientId]);
  } catch (expection) {
    print('_SendSignal Excpection');
    print(expection);
  }
}

class RTCIceServer {
  String Urls;
  String Username;
  String Credential;

  RTCIceServer(this.Urls, this.Username, this.Credential);

  RTCIceServer.fromJson(Map<String, dynamic> json)
      : Urls = json['urls'],
        Username = json['username'],
        Credential = json['credential'];

  Map<String, dynamic> toJson() =>
      {'Urls': Urls, 'Username': Username, 'Credential': Credential};
}

class IUser {
  String userName;
  String connectionId;

  IUser(this.userName, this.connectionId);

  IUser.fromJson(Map<String, dynamic> json)
      : userName = json['userName'],
        connectionId = json['connectionId'];

  Map<String, dynamic> toJson() =>
      {'userName': userName, 'connectionId': connectionId};
}

class UserRespond {
  String roomName;
  List<IUser> users;

  UserRespond({this.roomName, this.users});

  factory UserRespond.fromJson(Map<String, dynamic> parsedJson) {
    var users = parsedJson['users'] as List;
    List<IUser> userList = users.map((i) => IUser.fromJson(i)).toList();

    return new UserRespond(roomName: parsedJson['roomName'], users: userList);
  }
}

class UserConnection {
  IUser user;
  bool isCurrentUser;
  RTCPeerConnection rtcConnection;
  BehaviorSubject<MediaStream> streamSub;
  ObserverList<MediaStream> streamObservable;
  bool creatingOffer = false;
  bool creatingAnswer = false;

  UserConnection(
      IUser user, bool isCurrentUser, RTCPeerConnection rtcConnection) {
    this.user = user;
    this.isCurrentUser = isCurrentUser;
    this.rtcConnection = rtcConnection;
    this.streamSub = new BehaviorSubject<MediaStream>();
    // this.streamObservable = streamSub.as;
  }

  setStream(stream) {
    this.streamSub.addStream(stream);
  }

  end() {
    if (this.rtcConnection != null) {
      this.rtcConnection.close();
    }
    if (this.streamSub.value != null) {
      this.setStream(null);
    }
  }
}

class ISignal {
  SignalType type;
  RTCSessionDescription sdp;
  RTCIceCandidate candidate;

  ISignal(
      {SignalType this.type,
      RTCSessionDescription this.sdp = null,
      RTCIceCandidate this.candidate = null}) {}

  ISignal.fromJson(Map<String, dynamic> parsedJson)
      : type = getStatusFromString(parsedJson['type']),
        sdp = parsedJson['sdp'] == null ? null : RTCSessionDescription.fromJson(parsedJson['sdp']),
        candidate = parsedJson['candidate'] == null ? null : RTCIceCandidate.fromJson(parsedJson['candidate']);

  Map<String, dynamic> toJson() => {
        'type': type.index.toString(),
        'sdp': sdp == null ? "{}" : sdp.toJson(),
        'candidate': candidate == null ? "{}" : candidate.toJson()
      };
}

enum SignalType { newIceCandidate, videoOffer, videoAnswer }

SignalType getStatusFromString(int statusAsString) {
  for (SignalType element in SignalType.values) {
    if (element.index == statusAsString) {
      return element;
    }
  }
  return null;
}

Future<RTCPeerConnection> createPeerConnection2(
    Map<String, dynamic> configuration,
    Map<String, dynamic> constraints) async {
  MethodChannel channel = WebRTC.methodChannel();

  Map<String, dynamic> defaultConstraints = {
    "mandatory": {},
    "optional": [
      {"DtlsSrtpKeyAgreement": true},
    ],
  };

  final Map<dynamic, dynamic> response = await channel.invokeMethod(
    'createPeerConnection',
    <String, dynamic>{
      'configuration': configuration,
      'constraints': constraints.length == 0 ? defaultConstraints : constraints
    },
  );

  String peerConnectionId = response['peerConnectionId'];
  return new RTCPeerConnection(partnerId, configuration);
}

Future<void> _signalReceived(List<Object> arguments) async {
  try {
    print('SignalReceived is Called !');
    print("1 : "+ arguments.first.toString());
    print("2 : " +arguments.last.toString());



   var userDecoded = json.decode(arguments.first);
   var signalDecoded = json.decode(arguments.last);
    var us = IUser.fromJson(userDecoded);
    var sign = ISignal.fromJson(signalDecoded);
    await _newSignal(us, sign);
    print('SignalReceived has ended !');
  } catch (exception) {
    print('SIGNAL RECEIVED ERROR');
    print(exception);
  }
}

_newSignal(IUser user, ISignal signal) async {
  try {
    print('WEBRTC : received signal ');

    if (signal.type == SignalType.newIceCandidate) {
      await receivedNewIceCandidate(user.connectionId, signal.candidate);
    } else if (signal.type == SignalType.videoOffer) {
      print('Video Offer');
      await receivedVideoOffer(user.connectionId, signal.sdp);
    } else if (signal.type == SignalType.videoAnswer) {
      print('Video Answer');
      await receivedVideoAnswer(user.connectionId, signal.sdp);
    }
  } catch (error) {
    print('_newSignal error');
    print(error);
  }
}

receivedVideoAnswer(String partnerClientId, RTCSessionDescription sdp) async {
  print("Call recipent has accepted the call !");
  var connection = await getConnection(partnerClientId);
  await connection.rtcConnection.setRemoteDescription(sdp);
  print("Remote description is set ! ....");
}

receivedVideoOffer(String partnerClientId, RTCSessionDescription sdp) async {
  print("Starting to accept invitation from " + partnerClientId);
  var connection = await getConnection(partnerClientId);
  if (connection.creatingAnswer) {
    print('Second answer not created !');
    return;
  }
  connection.creatingAnswer = true;
  try {
    print('set Remote Description');
    await connection.rtcConnection.setRemoteDescription(sdp);
    print('create answer');
    var answer = await connection.rtcConnection.createAnswer(constraints);
    print('set local descriptor ' + answer.toString());
    var desc =  await connection.rtcConnection.getLocalDescription();
    await _sendSignal(
        new ISignal(
            type: SignalType.videoAnswer,
            sdp: desc),
        partnerClientId);
  } catch (expection) {}

  connection.creatingAnswer = false;
}

receivedNewIceCandidate(
    String partnerClientId, RTCIceCandidate candidate) async {
  try {
    print('Adding received Candidate with Id ' + partnerClientId);

    var connection = await createConnection(partnerClientId);
    await connection.rtcConnection.addCandidate(candidate);
  } catch (exception) {
    print(exception);
  }
}

Future<void> _callToUserList(List<Object> parameters) async {
  print("CallUserList -> Called on client ");
  Map<String, dynamic> map = {};
  map['roomName'] = parameters[0];
  map['users'] = parameters[1];
  var response = UserRespond.fromJson(map);
  if (currentRoomName == response.roomName) {
    response.users.forEach((user) => {
          if (!_connections.containsKey(user.connectionId) &&
              user.connectionId != currentConnectionId)
            {_initiateOffer(user)}
        });
  }
}

Future<void> _updateUserList(List<Object> parameters) async {
  print("UpdateUserList -> Called on client ");

  Map<String, dynamic> map = {};
  map['roomName'] = parameters[0];
  map['users'] = parameters[1];
  var response = UserRespond.fromJson(map);
  if (currentRoomName == response.roomName) {
    _connections.forEach((key, value) => {
          if (response.users.any((p) => p.connectionId == key) == false)
            {_closeVideoCall(key)}
        });
  }
}

_closeVideoCall(String key) {
  var connection = _connections[key];
  if (connection != null) {
    connection.end();
  }
  _connections.remove(key);
}

_closeAllVideoCalls() {
  _connections.forEach((k, v) => {_closeVideoCall(k)});
}
