import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/webrtc.dart';
import 'package:rxdart/rxdart.dart';
import 'package:signalr_client/signalr_client.dart';
import 'package:logging/logging.dart';
import 'package:signalr_client/signalr_client.dart';

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
HubConnection _hubConnection;
String currentConnectionId;
String currentRoomName = "Test1";
MediaStream currentMediaStream;
bool connected = false;
Map<String,UserConnection> _connections = new Map<String,UserConnection>();
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
    sleep(Duration(seconds:2));
    _connect();

    // TODO: implement initState
    super.initState();
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.display1,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}

_connect() async {
  // The location of the SignalR Server.
  final serverUrl = "https://4d04aa8a.ngrok.io/sgr/rtc";

  Logger.root.level = Level.ALL;

  Logger.root.onRecord.listen((LogRecord rec) {
  print('${rec.level.name}: ${rec.time}: ${rec.message}');
});

final hubProtLogger = Logger("SignalR - hub");

  var httpOptions = new HttpConnectionOptions(logger: hubProtLogger );
// Creates the connection by using the HubConnectionBuilder.
  _hubConnection = HubConnectionBuilder().withUrl(serverUrl , options: httpOptions).build();

  await _hubConnection.start();
// When the connection is closed, print out a message to the console.
  _hubConnection
      .onclose((error) => print("Connection Closed " + error.toString()));

  if (_hubConnection.state == HubConnectionState.Connected) {
    currentConnectionId = await _hubConnection.invoke('GetConnectionId');
    connected = true;
    _hubConnection.on('callToUserList', _callToUserList);
    _hubConnection.invoke('Join', args: <Object>["Test123124", "Test1"]);
  } else
    return;
}

Future<void> _callToUserList(List<Object> parameters) async {
  print("CallUserList -> Called on client ");
  Map<String, dynamic> map = {};
  map['roomName'] = parameters[0];
  map['users'] = parameters[1];
  var response = UserRespond.fromJson(map);
  if(currentRoomName == response.roomName){
   response.users.forEach(
      (user) => {
         if(!_connections.containsKey(user.connectionId) && user.connectionId != currentConnectionId){
          _initiateOffer(user)
         }
      }
   );
  }

}

Future<void> _initiateOffer(IUser acceptingUser) async {
  var partnerClientId = acceptingUser.connectionId;
  print('Initiate offer to ' + acceptingUser.connectionId);

  final iceServers = await getIceServers();
   List<RTCIceServer> serversList = iceServers.map((i) => RTCIceServer.fromJson(i)).toList();
  // var connection = getConnection(acceptingUser.connectionId, serversList);
}


// UserConnection getConnection(String connectionId, List<RTCIceServer> iceServers) {
//   var connection = _connections.keys(connectionId) || createConnection(connectionId,iceServers);
//   return connection;
// }

Future<List<dynamic>> getIceServers() async {
  var results =  await _hubConnection.invoke('GetIceServers') as List;
  return results;
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

    return new UserRespond(
        roomName: parsedJson['roomName'], users: userList);
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

  constructor(user, isCurrentUser, rtcConnection) {
    this.user = user;
    this.isCurrentUser = isCurrentUser;
    this.rtcConnection = rtcConnection;
    this.streamSub = new BehaviorSubject<MediaStream>();
    // this.streamObservable = this.streamSub();
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
