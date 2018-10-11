import 'dart:collection';
import 'dart:html';
import 'dart:async';
import 'dart:math';

import 'package:angular/angular.dart';
import 'package:deployment_manager/src/components/weekview/event/weekview_event.dart';

@Component(selector: "week-view", templateUrl: "weekview_component.html", styleUrls: ["weekview_component.css"], directives: [coreDirectives])
class WeekViewComponent implements OnInit, OnDestroy {
  static final int _DEFAULT_FONT_SIZE = 16;

  /// Maximum day in a range of monday to sunday = [0; 6] -> 6 is last day.
  static final int _MAX_DAY = 6;

  // TODO Add support for i18n
  static final List<String> _WEEK_DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

  @ViewChild("canvas", read: HtmlElement)
  HtmlElement canvasElement;
  CanvasElement _canvas;

  @ViewChild("canvasWrapper", read: HtmlElement)
  HtmlElement canvasWrapper;
  ResizeObserver _canvasWrapperResizeObserver;

  CanvasRenderingContext2D _context;

  num _width = 0;
  num _height = 0;
  num _widthHiDPI = 0;
  num _heightHiDPI = 0;

  int _animationFrameRequestId = -1;

  /// Bounding boxes of the previously drawn day panels.
  List<BoundingBox> _bounds;

  bool _isDayMouseDown = false;
  bool _hasDaySelection = false;
  int _dragEventStartDay;
  int _dragEventEndDay;
  Point<num> _dragEventStart;
  Point<num> _dragEventEnd;
  int _draggedStepCount = 0;
  int _draggedStepOffset = 0;
  int _oldDraggedStepCount = 0;
  StreamController<WeekViewEvent> _daySelectionChangeStreamController = StreamController.broadcast(sync: true);

  List<_EventHolder> _selectedEvents = List<_EventHolder>();
  StreamController<WeekViewEvent> _eventSelectionChangeStreamController = StreamController.broadcast(sync: true);

  /// Events are split up for each day for a efficient lookup.
  Map<int, List<_DayEventPart>> _eventsPerDay;
  List<int> _columnCountPerDay;

  /*
   * INPUT ATTRIBUTES
   */

  int _dayCount = 7;
  int _startHour = 0;
  int _endHour = 24;

  /*
   * INPUT ATTRIBUTES END
   */

  @override
  void ngOnInit() {
    _initCanvas();
  }

  @override
  void ngOnDestroy() {
    _canvasWrapperResizeObserver.unobserve(canvasWrapper);
  }

  void _render(num timestamp) {
    _animationFrameRequestId = -1;

    _bounds = List<BoundingBox>(); // Reinitialize bounds.

    _oldDraggedStepCount = _draggedStepCount;
    _draggedStepCount = 0;
    _draggedStepOffset = 0;

    _draw(timestamp);
  }

  void _draw(num timestamp) {
    _context.clearRect(0, 0, _widthHiDPI, _heightHiDPI);

    double width = _widthHiDPI;
    double height = _heightHiDPI;

    double timelineWidth = _drawTimeline(height, timestamp);

    _drawDays(Rectangle(timelineWidth, 0.0, width - timelineWidth, height), timestamp);
  }

  double _drawTimeline(double height, num timestamp) {
    int hourCount = _endHour - _startHour;
    double inset = pixelRatio * 5;
    double maxStringWidth = 0.0;

    _context.save();

    _context.font = "${defaultFontSize}px sans-serif";
    _context.textAlign = "right";
    _context.textBaseline = "middle";
    _context.setFillColorRgb(100, 100, 100);

    List<String> hourStrings = new List<String>();
    for (int hour = _startHour; hour <= _endHour; hour++) {
      String hourString = "${hour}:00";
      hourStrings.add(hourString);

      double stringWidth = _getTextWidth("${hour}:00");

      if (stringWidth > maxStringWidth) {
        maxStringWidth = stringWidth;
      }
    }

    double width = maxStringWidth + 2 * inset;

    double offsetY = _getDayHeaderSize();
    height -= offsetY;
    _context.translate(width - inset, offsetY);

    double heightPerHour = height / hourCount;
    for (int i = 0; i < hourStrings.length; i++) {
      if (i == hourStrings.length - 1) {
        _context.textBaseline = "bottom";
      }
      _context.fillText(hourStrings[i], 0.0, heightPerHour * i);
    }

    _context.restore();

    return width;
  }

  double _getTextWidth(String text) {
    return _context.measureText(text).width;
  }

  _drawDays(Rectangle<double> bounds, num timestamp) {
    _context.save();

    double dayWidth = bounds.width / _dayCount;
    double dayHeight = bounds.height;

    // For each week day.
    for (int day = 0; day < _dayCount; day++) {
      _drawDay(day, Rectangle(bounds.left + dayWidth * day, bounds.top, dayWidth, dayHeight), timestamp);
    }

    _context.restore();
  }

  void _drawDay(int day, Rectangle<double> bounds, num timestamp) {
    _context.save();

    _context.translate(bounds.left, bounds.top);

    double width = bounds.width;
    double height = bounds.height;

    bool isLastDay = day == _dayCount - 1;

    _context.save();
    double dayHeaderSize = _drawDayHeader(day, bounds, timestamp);
    _context.restore();

    height -= dayHeaderSize;
    _context.translate(0.0, dayHeaderSize);

    double offsetY = bounds.top + dayHeaderSize;
    var newBounds = Rectangle(bounds.left, offsetY, width, height);
    _addBounds(_BoundingBoxType.DAY, newBounds, day);

    _context.save();
    _drawDayTimeline(day, newBounds, timestamp);
    _context.restore();

    if (!isLastDay) {
      // Draw right border line
      _context.lineWidth = pixelRatio;
      _context.setStrokeColorRgb(220, 230, 240);
      _context.beginPath();
      _context.moveTo(width, 0.0);
      _context.lineTo(width, height);
      _context.stroke();
    }

    if (_hasDaySelection) {
      var startDay = min(_dragEventStartDay, _dragEventEndDay);
      var endDay = max(_dragEventStartDay, _dragEventEndDay);

      if (day >= startDay && day <= endDay) {
        double startY = 0.0;
        double endY = height;

        if (startDay == endDay) {
          startY = min(_dragEventStart.y, _dragEventEnd.y) * pixelRatio - offsetY;
          endY = max(_dragEventStart.y, _dragEventEnd.y) * pixelRatio - offsetY;
        } else if (day == _dragEventStartDay) {
          if (_dragEventStartDay < _dragEventEndDay) {
            startY = _dragEventStart.y * pixelRatio - offsetY;
          } else {
            endY = _dragEventStart.y * pixelRatio - offsetY;
          }
        } else if (day == _dragEventEndDay) {
          if (_dragEventStartDay < _dragEventEndDay) {
            endY = _dragEventEnd.y * pixelRatio - offsetY;
          } else {
            startY = _dragEventEnd.y * pixelRatio - offsetY;
          }
        }

        // Normalize to steps.
        int stepCount = _getStepCountPerDay();
        double stepHeight = height / stepCount;

        var startYStep = _getNearestStep(stepCount, height, startY);
        var endYStep = _getNearestStep(stepCount, height, endY);

        _draggedStepCount += endYStep - startYStep;

        if (day == startDay) {
          _draggedStepOffset = startYStep;
        }

        startY = startYStep * stepHeight;
        endY = endYStep * stepHeight;

        double dragHeight = endY - startY;

        double lineWidth = pixelRatio * 3;
        _context.lineWidth = lineWidth;
        _context.setStrokeColorRgb(63, 143, 210);
        _context.setFillColorRgb(63, 143, 210, 0.3);
        if (dragHeight > 0) {
          _context.strokeRect(lineWidth, startY + lineWidth, width - lineWidth * 2, dragHeight - lineWidth * 2);
          _context.fillRect(lineWidth, startY + lineWidth, width - lineWidth * 2, dragHeight - lineWidth * 2);
        } else {
          // Draw just a little line.
          _context.beginPath();
          _context.moveTo(0.0, startY);
          _context.lineTo(width, startY);
          _context.stroke();
        }

        if (day == _dragEventEndDay) {
          // Draw hour label

          _context.font = "${defaultFontSize}px sans-serif";
          _context.textAlign = "center";
          _context.textBaseline = "middle";

          String label = _formatStepCountToTime(_oldDraggedStepCount);
          double labelWidth = _getTextWidth("00h 00m") / 2;

          var pos = _dragEventEnd.y * pixelRatio - offsetY;

          _context.setFillColorRgb(0, 0, 0);
          _context.beginPath();
          _context.arc(width / 2, pos - lineWidth / 2, labelWidth, 0, 2 * pi);
          _context.fill();

          _context.setFillColorRgb(255, 255, 255);
          _context.fillText(label, width / 2, pos - lineWidth / 2);
        }
      }
    }

    _context.restore();
  }

  String _formatStepCountToTime(int stepCount) {
    int stepMinutes = 60 ~/ 4;

    int minutes = stepCount * stepMinutes;
    int hours = minutes ~/ 60;

    minutes -= hours * 60;

    return "${hours}h ${minutes}m";
  }

  int _getStepCountPerDay() => (_endHour - _startHour) * 4;

  int _getNearestStep(int steps, double size, double toMatch) {
    double stepHeight = size / steps;

    return max(0, (toMatch / stepHeight).round());
  }

  void _drawDayTimeline(int day, Rectangle<double> bounds, num timestamp) {
    _drawDayTimelineBackground(day, bounds.width, bounds.height, timestamp);
    _drawDayTimelineHourLines(day, bounds.width, bounds.height, timestamp);
    _drawDayEvents(day, bounds, timestamp);
  }

  void _drawDayEvents(day, Rectangle<double> bounds, timestamp) {
    _context.save();

    _context.font = "${defaultFontSize}px sans-serif";
    _context.textAlign = "left";
    _context.textBaseline = "top";

    double inset = 3 * pixelRatio;

    if (_eventsPerDay != null) {
      List<_DayEventPart> eventParts = _eventsPerDay[day];
      int columnCount = _columnCountPerDay[day];

      if (eventParts != null && eventParts.isNotEmpty) {
        double hourHeight = bounds.height / (_endHour - _startHour);

        // Draw each event.
        for (var part in eventParts) {
          WeekViewEvent event = part.holder.event;

          // Validate event.
          if (event.startHour < _startHour) {
            throw new Exception("Cannot draw event because the start hour is $_startHour while the event starts at hour ${event.startHour}");
          }
          if (event.endHour > _endHour) {
            throw new Exception("Cannot draw event because the end hour is $_endHour while the event ends at hour ${event.endHour}");
          }

          var startY = 0.0;
          var endY = bounds.height;
          if (day == event.startDay || day == event.endDay) {
            // Draw event partly of the day.

            if (day == event.startDay) {
              var hourOffset = (event.startHour + (event.startMinute / 60)) - _startHour;
              startY = hourOffset * hourHeight;
            }

            if (day == event.endDay) {
              var hourOffset = _endHour - (event.endHour + (event.endMinute / 60));
              endY -= hourOffset * hourHeight;
            }
          }

          var width = bounds.width;
          var height = endY - startY;

          var columnInset = 0.0;
          if (columnCount > 1) {
            // There are overlaying events. Draw event in its own column.
            width /= columnCount;
            columnInset = part.column * width;
          }

          var eventBounds = Rectangle(bounds.left + inset + columnInset, bounds.top + startY + inset, width - inset * 2, height - inset * 2);

          _addBounds(_BoundingBoxType.EVENT, eventBounds, part, 10);

          double lineWidth = 2 * pixelRatio;

          if (part.holder.isSelected) {
            _context.setStrokeColorRgb(63, 143, 210);
            lineWidth *= 1.5;
          } else {
            _context.setStrokeColorRgb(220, 220, 220);
          }

          _context.setFillColorRgb(255, 255, 255);

          _context.lineWidth = lineWidth;
          _context.fillRect(inset + columnInset, startY + inset, eventBounds.width, eventBounds.height);
          _context.strokeRect(
              lineWidth + inset + columnInset, startY + lineWidth + inset, eventBounds.width - lineWidth * 2, eventBounds.height - lineWidth * 2);

          double textInset = 3 * pixelRatio;
          double fullInset = inset + textInset;

          _context.setFillColorRgb(30, 30, 30);
          _context.fillText(event.description, columnInset + inset * 2 + textInset, startY + fullInset * 2, eventBounds.width - fullInset * 2);
        }
      }
    }

    _context.restore();
  }

  void _drawDayTimelineBackground(int day, double width, double height, num timestamp) {
    if (day.isEven) {
      _context.setFillColorRgb(255, 255, 255);
    } else {
      _context.setFillColorRgb(250, 250, 250);
    }

    _context.fillRect(0.0, 0.0, width, height);
  }

  void _drawDayTimelineHourLines(int day, double width, double height, num timestamp) {
    _context.save();

    double inset = pixelRatio * 10;

    _context.setStrokeColorRgb(230, 230, 230);
    _context.lineWidth = pixelRatio;

    int hourCount = _endHour - _startHour;
    double hourHeight = height / hourCount;

    for (int i = 0; i < hourCount - 1; i++) {
      _context.translate(0.0, hourHeight);

      _context.beginPath();
      _context.moveTo(inset, 0.0);
      _context.lineTo(width - inset, 0.0);
      _context.stroke();
    }

    _context.restore();
  }

  double _drawDayHeader(int day, Rectangle<double> dayBounds, num timestamp) {
    double height = _getDayHeaderSize();
    double width = dayBounds.width;

    _addBounds(_BoundingBoxType.DAY_HEADER, Rectangle(dayBounds.left, dayBounds.top, width, height), day);

    bool isCurrentDay = day == DateTime.now().weekday - 1;

    if (isCurrentDay) {
      _context.setFillColorRgb(255, 102, 140);
    } else {
      _context.setFillColorRgb(255, 51, 102);
    }

    _context.fillRect(0.0, 0.0, width, height);

    _context.font = "${defaultFontSize}px sans-serif";
    _context.textAlign = "center";
    _context.textBaseline = "middle";

    _context.setFillColorRgb(255, 255, 255);
    _context.fillText(_getNameForDay(day), width / 2, height / 2);

    return height;
  }

  double _getDayHeaderSize() => defaultFontSize * 2;

  String _getNameForDay(int day) => _WEEK_DAYS[day];

  void _initCanvas() {
    _canvas = canvasElement as CanvasElement;

    _canvas.addEventListener("mousedown", _onMouseDown);
    _canvas.addEventListener("mousemove", _onMouseMove);
    _canvas.addEventListener("mouseup", _onMouseUp);

    _context = _canvas.getContext("2d");

    // Observe canvas wrapper size changes and align the canvas size to it.
    _canvasWrapperResizeObserver = ResizeObserver(_onCanvasShouldResize);
    _canvasWrapperResizeObserver.observe(canvasWrapper);

    _invalidate();
  }

  void _onCanvasShouldResize(List<ResizeObserverEntry> entries, ResizeObserver observer) {
    if (entries.isNotEmpty) {
      ResizeObserverEntry entry = entries[0];

      _width = entry.contentRect.width;
      _height = entry.contentRect.height;

      _updateCanvasSize(_width, _height);
    }
  }

  _updateCanvasSize(num width, num height) {
    _widthHiDPI = width * pixelRatio;
    _heightHiDPI = height * pixelRatio;

    _canvas.width = _widthHiDPI;
    _canvas.height = _heightHiDPI;

    _updateCanvasStyles();

    _invalidate();
  }

  void _updateCanvasStyles() {
    _canvas.style.width = "${_width}px";
    _canvas.style.height = "${_height}px";
  }

  /// Schedule the canvas to redraw itself.
  void _invalidate() {
    if (_animationFrameRequestId == -1) {
      _animationFrameRequestId = window.requestAnimationFrame(_render);
    }
  }

  double get pixelRatio => window.devicePixelRatio;

  double get defaultFontSize => _DEFAULT_FONT_SIZE * pixelRatio;

  void _onMouseDown(Event event) {
    _onMouseAction(_MouseAction.MOUSEDOWN, event);
  }

  void _onMouseUp(Event event) {
    _onMouseAction(_MouseAction.MOUSEUP, event);
  }

  void _onMouseMove(Event event) {
    _onMouseAction(_MouseAction.MOUSEMOVE, event);
  }

  void _onMouseAction(_MouseAction action, MouseEvent event) {
    Point<num> position = _getLocalPoint(event);

    if (_bounds != null) {
      var boxes = _getBoundsForPosition(position);

      if (boxes != null && boxes.isNotEmpty) {
        for (var box in boxes) {
          if (!_mouseActionOnBox(action, box, position)) {
            break;
          }
        }
      }
    }
  }

  void _deselectAll() {
    _hasDaySelection = false;

    if (_selectedEvents.isNotEmpty) {
      for (var holder in _selectedEvents) {
        holder.isSelected = false;
      }

      _selectedEvents.clear();
    }
  }

  bool _mouseActionOnBox(_MouseAction action, BoundingBox box, Point<num> position) {
    switch (box.type) {
      case _BoundingBoxType.DAY:
        return _onDayMouseAction(action, box.object as int, position);
        break;
      case _BoundingBoxType.DAY_HEADER:
        break;
      case _BoundingBoxType.EVENT:
        return _onEventMouseAction(action, box.object as _DayEventPart, position);
        break;
      default:
      // No action defined.
    }

    return true;
  }

  bool _onDayMouseAction(_MouseAction action, int day, Point<num> position) {
    switch (action) {
      case _MouseAction.MOUSEDOWN:
        _isDayMouseDown = true;

        _deselectAll();

        _dragEventStartDay = day;
        _dragEventStart = position;

        _invalidate();
        break;
      case _MouseAction.MOUSEUP:
        _isDayMouseDown = false;

        _dragEventEnd = position;
        _dragEventEndDay = day;

        var newEvent = _createEventFromCurrentSelection();
        if (newEvent != null) {
          _daySelectionChangeStreamController.add(newEvent);
        }

        _invalidate();
        break;
      case _MouseAction.MOUSEMOVE:
        if (_isDayMouseDown) {
          _hasDaySelection = true;

          _dragEventEnd = position;
          _dragEventEndDay = day;

          _invalidate();
        }
        break;
      default:
    }

    return true;
  }

  WeekViewEvent _createEventFromCurrentSelection() {
    if (_draggedStepCount != 0) {
      int startDay = min(_dragEventStartDay, _dragEventEndDay);
      int endDay = max(_dragEventStartDay, _dragEventEndDay);

      double hourOffset = _draggedStepOffset / 4;
      double hours = _draggedStepCount / 4; // Quarter steps

      int startHour = hourOffset.toInt();
      int startMinute = ((hourOffset - startHour) * 60).toInt();

      int endHour = 0;
      int endMinute = 0;
      if (startDay == endDay) {
        double endHourDouble = hourOffset + hours;

        endHour = endHourDouble.toInt();
        endMinute = ((endHourDouble - endHour) * 60).toInt();
      } else {
        int hoursPerDay = _endHour - _startHour;
        int dayCount = endDay - startDay;

        hours -= hoursPerDay - hourOffset; // Remove hours of first day.
        hours -= (dayCount - 1) * hoursPerDay; // Remove hours of intermediate days.

        // Remaining hours are now the real end hour.
        endHour = hours.toInt();
        endMinute = ((hours - endHour) * 60).toInt();
      }

      return SimpleWeekViewEvent(
        startDay: startDay,
        startHour: startHour + _startHour,
        startMinute: startMinute,
        endDay: endDay,
        endHour: endHour + _startHour,
        endMinute: endMinute,
        description: null
      );
    }

    return null;
  }

  bool _onEventMouseAction(_MouseAction action, _DayEventPart part, Point<num> position) {
    switch (action) {
      case _MouseAction.MOUSEDOWN:
        var holder = part.holder;

        _deselectAll();
        holder.isSelected = true;
        _selectedEvents.add(holder);

        _eventSelectionChangeStreamController.add(holder.event);

        _invalidate();

        return false;
      case _MouseAction.MOUSEUP:
        break;
      case _MouseAction.MOUSEMOVE:
        break;
      default:
    }

    return true;
  }

  /// Get local point on the canvas of the passed mouse [event].
  Point<num> _getLocalPoint(MouseEvent event) {
    Rectangle<num> rect = _canvas.getBoundingClientRect();

    return Point(event.client.x - rect.left, event.client.y - rect.top);
  }

  Iterable<BoundingBox> _getBoundsForPosition(Point<num> position) {
    if (_bounds != null) {
      var list =  _bounds.where((box) => box.bounds.containsPoint(position)).toList();

      list.sort((box1, box2) {
        return box1.zIndex - box2.zIndex;
      });

      return list;
    }

    return null;
  }

  /// Add bounds to the bounds list.
  /// Specify the [type] of the box to later decide what object is in the box.
  /// Optionally you can provide a zIndex so that only higher bounding boxes will be used when executing mouse actions.
  void _addBounds(_BoundingBoxType type, Rectangle<double> rect, Object object, [int zIndex = 0]) {
    var normalizedRect = Rectangle(rect.left / pixelRatio, rect.top / pixelRatio, rect.width / pixelRatio, rect.height / pixelRatio);

    _bounds.add(BoundingBox(type, normalizedRect, object, zIndex));
  }

  @Input()
  void set startHour(int value) {
    _startHour = value;

    _invalidate();
  }

  @Input()
  void set endHour(int value) {
    _endHour = value;

    _invalidate();
  }

  @Input()
  void set dayCount(int value) {
    _dayCount = value;

    _invalidate();
  }

  @Input()
  void set events(List<WeekViewEvent> events) {
    _eventsPerDay = new HashMap<int, List<_DayEventPart>>();

    // Split events to day parts.
    for (var event in events) {
      var holder = _EventHolder(event);
      for (int day = event.startDay; day <= event.endDay; day++) {
        _eventsPerDay.putIfAbsent(day, () => List<_DayEventPart>()).add(_DayEventPart(holder, day));
      }
    }

    _columnCountPerDay = List.filled(_MAX_DAY + 1, 0);
    for (var dayParts in _eventsPerDay.values) {
      if (dayParts != null && dayParts.isNotEmpty) {
        // Sort day parts by their length. If they are equal, sort which ones underlying event is earlier.
        dayParts.sort((part1, part2) {
          int result = part2.length.compareTo(part1.length);

          if (result == 0) {
            // Compare the parts underlying events start dates.
            result = _compareStartDates(part1.holder.event.startHour,
                part1.holder.event.startMinute,
                part2.holder.event.startHour,
                part2.holder.event.startMinute);
          }

          return result;
        });

        // Check if day part events are overlaying and in this case modify the column.
        var columnLookup = HashMap<int, List<_DayEventPart>>();
        int maxColumn = 0;
        for (var dayPart in dayParts) {
          bool isOrdered = false;
          int column = 0;
          var columnParts = columnLookup.putIfAbsent(column, () => List<_DayEventPart>());

          while (!isOrdered) {
            if (columnParts.isEmpty || !columnParts.any((otherPart) => _areDayPartsOverlaying(dayPart, otherPart))) {
              isOrdered = true;
            } else {
              // Day parts overlap.
              columnParts = columnLookup.putIfAbsent(++column, () => List<_DayEventPart>()); // Get next column parts
            }
          }

          dayPart.column = column;

          if (column > maxColumn) {
            maxColumn = column;
          }

          columnParts.add(dayPart);
        }

        _columnCountPerDay[dayParts.first.day] = maxColumn + 1;
      }
    }

    _invalidate();
  }

  bool _areDayPartsOverlaying(_DayEventPart part1, _DayEventPart part2) => _intervalsOverlap(part1.offset, part1.offset + part1.length, part2.offset, part2.offset + part2.length);

  /// Check if two intervals [a; b] and [x; z] are overlaying each other.
  bool _intervalsOverlap(double a, double b, double x, double z) => a <= z && x <= b;

  /// Compare which of the two is first or equal.
  int _compareStartDates(int startHour1, int startMinute1, int startHour2, int startMinute2) {
    int result = startHour1.compareTo(startHour2);

    if (result == 0) {
      result = startMinute1.compareTo(startMinute2);
    }

    return result;
  }

  @Output("rangeSelection")
  Stream<WeekViewEvent> get rangeSelectionChange => _daySelectionChangeStreamController.stream;

  @Output("eventSelection")
  Stream<WeekViewEvent> get eventSelectionChange => _eventSelectionChangeStreamController.stream;
}

class BoundingBox {
  final _BoundingBoxType type;
  final Rectangle<double> bounds;
  final Object object;
  final int zIndex;

  BoundingBox(this.type, this.bounds, this.object, this.zIndex);
}

/// Event which is part of a day.
/// It may be part of an event which is longer than one day.
class _DayEventPart {
  final _EventHolder holder;
  final int day;
  int column = 0;

  double _length = 0.0;
  double _offset = 0.0;

  _DayEventPart(this.holder, this.day){
    _init();
  }

  void _init() {
    var event = holder.event;

    double start = 0.0;
    double end = 24.0;

    if (day == event.startDay) {
      start = event.startHour + event.startMinute / 60;
    }
    if (day == event.endDay){
      end = event.endHour + event.startMinute / 60;
    }

    _offset = start;
    _length = end - start;
  }


  /// Length of the event on this day in hours.
  double get length => _length;

  double get offset => _offset;

}

/// A event holder holds an event.
/// It adds some attributes to the event which are only needed during runtime.
class _EventHolder {
  final WeekViewEvent event;
  bool isSelected = false;

  _EventHolder(this.event);
}

enum _BoundingBoxType { DAY, DAY_HEADER, EVENT }

enum _MouseAction { MOUSEDOWN, MOUSEUP, MOUSEMOVE }
