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
            var idx = currentEvent.data.lastIndexOf("\n");

            currentEvent.data = idx != -1 ? currentEvent.data.substring(0, idx) : currentEvent.data;            
          }
          controller.add(currentEvent);
          currentEvent = new Event();
          return;
        }
        // match the line prefix and the value
        var delimiterIdx = line.indexOf(": ");

        String field = line.substring(0, delimiterIdx);
        String value = line.substring(delimiterIdx + 1).trim() ?? "";

        if (field.isEmpty) {
          // lines starting with a colon are to be ignored
          return;
        }
        switch (field) {
          case "event":
            currentEvent.event = value;
            break;
          case "data":
            currentEvent.data = (currentEvent.data ?? "") + value + "\n";
            break;
          case "id":
            currentEvent.id = value;
            break;
          case "retry":
            if (retryIndicator != null) {
              retryIndicator(new Duration(milliseconds: int.parse(value)));
            }
            break;
        }
      });
    });
    return controller.stream;
  }
}
