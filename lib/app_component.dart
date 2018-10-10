import 'package:angular/angular.dart';
import 'package:angular_components/material_button/material_button.dart';
import 'package:deployment_manager/src/components/weekview/event/weekview_event.dart';
import 'package:deployment_manager/src/components/weekview/weekview_component.dart';

@Component(
  selector: "deployment-manager",
  styleUrls: ["app_component.css"],
  templateUrl: "app_component.html",
  directives: [WeekViewComponent, MaterialButtonComponent]
)
class AppComponent {

  List<WeekViewEvent> events = [];

  WeekViewEvent _selectedEvent;
  WeekViewEvent _rangeSelection;

  void onRangeSelectionChanged(WeekViewEvent newSelection) {
    _rangeSelection = newSelection;
    print("${newSelection.startDay} ${newSelection.startHour} ${newSelection.startMinute} to ${newSelection.endDay} ${newSelection.endHour} ${newSelection.endMinute}");
  }

  void onEventSelectionChanged(WeekViewEvent event) {
    _selectedEvent = event;
    print("Selected ${event.description}");
  }

  void createEvent() {
    List<WeekViewEvent> newEvents = List.from(events);
    newEvents.add(_rangeSelection);

    events = newEvents;
  }

  void deleteEvent() {
    List<WeekViewEvent> newEvents = List.from(events);
    newEvents.remove(_selectedEvent);

    events = newEvents;
  }

}
