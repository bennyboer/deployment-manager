abstract class WeekViewEvent {

  /// Start day of the event.
  int get startDay;

  /// Start hour of the event.
  int get startHour;

  /// Start minute of the event.
  int get startMinute;

  /// End day of the event.
  int get endDay;

  /// End hour of the event.
  int get endHour;

  /// End minute of the event.
  int get endMinute;

  /// Description of the event.
  String get description;

}

class SimpleWeekViewEvent implements WeekViewEvent {

  int startDay;
  int startHour;
  int startMinute;

  int endDay;
  int endHour;
  int endMinute;

  String description;

  SimpleWeekViewEvent({
    this.startDay,
    this.startHour,
    this.startMinute,
    this.endDay,
    this.endHour,
    this.endMinute,
    this.description
  });

}
