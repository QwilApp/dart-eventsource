library eventsource;

export "src/event.dart";

import "dart:async";
import "dart:convert";
import 'dart:io';

import "package:http/http.dart" as http;
import "package:http/src/utils.dart" show encodingForCharset;
import "package:http_parser/http_parser.dart" show MediaType;

import "src/event.dart";
import "src/decoder.dart";

enum EventSourceReadyState {
  CONNECTING,
  OPEN,
  CLOSED,
}

class EventSourceSubscriptionException extends Event implements Exception {
  int statusCode;
  String message;

  @override
  String get data => "$statusCode: $message";

  EventSourceSubscriptionException(this.statusCode, this.message)
      : super(event: "error");
}

/// An EventSource client that exposes a [Stream] of [Event]s.
class EventSource extends Stream<Event> {
  // interface attributes

  final Uri url;

  EventSourceReadyState get readyState => _readyState;

  Stream<Event> get onOpen => this.where((e) => e.event == "open");
  Stream<Event> get onMessage => this.where((e) => e.event == "message");
  Stream<Event> get onError => this.where((e) => e.event == "error");

  // internal attributes

  StreamController<Event> _streamController =
      new StreamController<Event>.broadcast();

  StreamController<EventSourceReadyState> _stateController =
      new StreamController<EventSourceReadyState>();

  EventSourceReadyState _readyState = EventSourceReadyState.CONNECTING;

  http.Client client;
  Duration _retryDelay = const Duration(milliseconds: 3000);
  String _lastEventId;
  EventSourceDecoder _decoder;
  Duration _timeout;
  List<Cookie> _cookies;

  /// Create a new EventSource by connecting to the specified url.
  static Future<EventSource> connect(url,
      {http.Client client, String lastEventId,
        Map<String, dynamic> query, List<Cookie> cookies, Duration timeout}) async {
    // parameter initialization
    String queryString = null;
    if(query != null && query.length > 0) {
      queryString = query.keys.map((k) => '$k=${query[k].toString()}').join('&');
    }
    url = url is Uri ? url : Uri.parse(url + (queryString != null ? '?${Uri.encodeFull(queryString)}' : ''));
    client = client ?? new http.Client();
    lastEventId = lastEventId ?? "";
    EventSource es = new EventSource._internal(url, client, lastEventId, cookies ?? List(), timeout ?? Duration(seconds: 5));
    try {
      await es._start();
    } catch (error) {
      es._retry(error);
    }
    return es;
  }

  EventSource._internal(this.url, this.client, this._lastEventId, this._cookies, this._timeout) {
    _decoder = new EventSourceDecoder(retryIndicator: _updateRetryDelay);
  }

  // proxy the listen call to the controller's listen call
  @override
  StreamSubscription<Event> listen(void onData(Event event),
          {Function onError, void onDone(), bool cancelOnError}) =>
    _streamController.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  
  StreamSubscription<EventSourceReadyState> listenState(void onData(EventSourceReadyState event)) =>
    _stateController.stream.listen(onData, cancelOnError: false);

  /// Attempt to start a new connection.
  Future _start() async {
    if(_readyState == EventSourceReadyState.CLOSED) {
      return;
    }
    _readyState = EventSourceReadyState.CONNECTING;
    _stateController.add(_readyState);
    var request = new http.Request("GET", url);
    request.headers["Cache-Control"] = "no-cache";
    request.headers["Accept"] = "text/event-stream";
    if (_lastEventId.isNotEmpty) {
      request.headers["Last-Event-ID"] = _lastEventId;
    }
    if(_cookies != null && _cookies.length > 0) {
      request.headers["Cookie"] = _cookies.map((c) => c.toString()).join('; ');
    }
    var response = await client.send(request);
    if (response.statusCode != 200) {
      // server returned an error
      var bodyBytes = await response.stream.toBytes();
      String body = _encodingForHeaders(response.headers).decode(bodyBytes);
      throw new EventSourceSubscriptionException(response.statusCode, body);
    }
    response.headers.keys.forEach((header) {
      if(header.toLowerCase() == 'set-cookie') {
        _cookies.add(Cookie.fromSetCookieValue(response.headers[header]));
      }
    });
    _readyState = EventSourceReadyState.OPEN;
    _stateController.add(_readyState);
    // start streaming the data
    response.stream.transform(_decoder).timeout(_timeout).listen((Event event) {
      _streamController.add(event);
      if(event.event == 'close') {
        _readyState = EventSourceReadyState.CLOSED;
        _stateController.add(_readyState);
      } else if (_readyState != EventSourceReadyState.OPEN) {
        _readyState = EventSourceReadyState.OPEN;
        _stateController.add(_readyState);
      }
      _lastEventId = event.id;
    },
        cancelOnError: false,
        onError: (err) {
          if(_readyState != EventSourceReadyState.CLOSED) {
            _stateController.add(EventSourceReadyState.CONNECTING);
            _retry(err);
          }
        },
        onDone: () {
          _readyState = EventSourceReadyState.CLOSED;
          _stateController.add(_readyState);
        });
  }

  /// Retries until a new connection is established. Uses exponential backoff.
  Future _retry(dynamic e) async {
    if(_readyState != EventSourceReadyState.CLOSED) {
      // try reopening with exponential backoff
      Duration backoff = _retryDelay;
      while (true) {
        await new Future.delayed(backoff);
        try {
          await _start();
          break;
        } catch (error) {
          _streamController.addError(error);
          backoff *= 2;
        }
      }
    }
  }

  void _updateRetryDelay(Duration retry) {
    _retryDelay = retry;
  }
}

/// Returns the encoding to use for a response with the given headers. This
/// defaults to [LATIN1] if the headers don't specify a charset or
/// if that charset is unknown.
Encoding _encodingForHeaders(Map<String, String> headers) =>
    encodingForCharset(_contentTypeForHeaders(headers).parameters['charset']);

/// Returns the [MediaType] object for the given headers's content-type.
///
/// Defaults to `application/octet-stream`.
MediaType _contentTypeForHeaders(Map<String, String> headers) {
  var contentType = headers['content-type'];
  if (contentType != null) return new MediaType.parse(contentType);
  return new MediaType("application", "octet-stream");
}
