library eventsource.src.decoder;

import "dart:async";
import "dart:convert";

import "event.dart";

typedef void RetryIndicator(Duration duration);

class EventSourceDecoder extends StreamTransformerBase<List<int>, Event> {
  RetryIndicator  retryIndicator;

  EventSourceDecoder({this.retryIndicator});

  Stream<Event> bind(Stream<List<int>> stream) {
    StreamController<Event> controller;
    controller = new StreamController(onListen: () {
      // the event we are currently building
      Event currentEvent = new Event();

      // This stream will receive chunks of data that is not necessarily a
      // single event. So we build events on the fly and broadcast the event as
      // soon as we encounter a double newline, then we start a new one.
      stream
        .transform(new Utf8Decoder())
        .transform(new LineSplitter())
        .listen((String line) {

        if (line.isEmpty) {
          // event is done
          // strip ending newline from data
          if (currentEvent.data != null) {
            final int idx = currentEvent.data.lastIndexOf("\n");

            currentEvent.data = idx != -1 ? currentEvent.data.substring(0, idx) : currentEvent.data;            
          }
          controller.add(currentEvent);
          currentEvent = new Event();
          return;
        }
        // match the line prefix and the value

        if (line.startsWith("event:")) {
          currentEvent.event = line.substring(6).trim();
        }
        else if (line.startsWith("data:")) {
          final String value = line.substring(5).trim() ?? "";

          currentEvent.data = (currentEvent.data ?? "") + value + "\n";
        }
        else if (line.startsWith("id:")) {
          currentEvent.id = line.substring(3).trim();
        }
        else if (line.startsWith("retry:")) {
          final String value = line.substring(6).trim();

          if (retryIndicator != null) {
            retryIndicator(new Duration(milliseconds: int.parse(value)));
          }
        }
        else {
          return;
        }
      });
    });
    return controller.stream;
  }
}
