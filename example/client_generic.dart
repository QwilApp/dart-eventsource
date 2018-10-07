import 'dart:io';

import "package:eventsource/eventsource.dart";

main() async {
//   Because EventSource uses the http package, all platforms for which http
//   works, will be able to use the generic method:

  EventSource eventSource =
      await EventSource.connect("http://example.org/events");
  // listen for events
  eventSource.listen((Event event) {
    print("New event:");
    print("  event: ${event.event}");
    print("  data: ${event.data}");
  });

  // If you know the last event.id from a previous connection, you can try this:

  String lastId = "iknowmylastid";
  eventSource = await EventSource.connect("http://example.org/events",
      lastEventId: lastId);
  // listen for events
  eventSource.listen((Event event) {
    print("New event:");
    print("  event: ${event.event}");
    print("  data: ${event.data}");
  });


  Map<String, dynamic> params = Map();
  params['msg'] = 'Hello world';
  List<Cookie> cookies = List();
  cookies.add(Cookie.fromSetCookieValue("name=value"));
  cookies.add(Cookie.fromSetCookieValue("name1=value1"));
  EventSource query = await EventSource.connect("https://www.strehle.de/tim/demos/stream.php",
      query: params, cookies: cookies);
  // listen for events
  query.listen((Event event) {
    print("New event:");
    print("  event: ${event.event}");
    print("  data: ${event.data}");
  }, cancelOnError: false);
  query.listenState((EventSourceReadyState state) {
    print('New state: ${state.toString()}');
  });
}
