library ng2_form_components.components.side_panel;

import 'dart:async';

import 'package:rxdart/rxdart.dart' as rx;
import 'package:dorm/dorm.dart';
import 'package:angular2/angular2.dart';

import 'package:ng2_form_components/src/components/interfaces/before_destroy_child.dart' show BeforeDestroyChild;

import 'package:ng2_form_components/src/components/animation/side_panel_animation.dart';

import 'package:ng2_form_components/src/components/internal/form_component.dart';

import 'package:ng2_state/ng2_state.dart' show SerializableTuple1, StatePhase, StateService;

@Component(
    selector: 'side-panel',
    templateUrl: 'side_panel.html',
    directives: const <Type>[SidePanelAnimation],
    providers: const <Type>[StateService],
    changeDetection: ChangeDetectionStrategy.OnPush,
    preserveWhitespace: false
)
class SidePanel<T extends Comparable<dynamic>> extends FormComponent<T> implements OnDestroy, BeforeDestroyChild {

  //-----------------------------
  // input
  //-----------------------------

  String _orientation = 'right';
  String get orientation => _orientation;
  @Input() set orientation(String value) {
    _orientation = value;
  }

  //-----------------------------
  // output
  //-----------------------------

  @override StreamController<bool> get beforeDestroyChild => _beforeDestroyChild$ctrl;

  final StreamController<bool> _beforeDestroyChild$ctrl = new StreamController<bool>.broadcast();
  final StreamController<bool> _isOpen$ctrl = new StreamController<bool>.broadcast();
  final StreamController<bool> _toggle$ctrl = new StreamController<bool>.broadcast();

  StreamSubscription<bool> _beforeDestroyChildSubscription;
  StreamSubscription<bool> _toggleStateSubscription;

  bool isOpen = false;

  //-----------------------------
  // constructor
  //-----------------------------

  SidePanel(
    @Inject(ChangeDetectorRef) ChangeDetectorRef changeDetector,
    @Inject(ElementRef) ElementRef elementRef,
    @Inject(StateService) StateService stateService) :
      super(changeDetector, elementRef, stateService) {
        _initStreams();
      }

  //-----------------------------
  // ng2 life cycle
  //-----------------------------

  @override Stream<Entity> provideState() => _isOpen$ctrl.stream
    .map((bool isOpen) => new SerializableTuple1<bool>()..item1 = isOpen);

  @override void receiveState(Entity entity, StatePhase phase) {
    final SerializableTuple1<bool> tuple = entity as SerializableTuple1<bool>;

    _isOpen$ctrl.add(tuple.item1);

    isOpen = tuple.item1;

    changeDetector.markForCheck();
  }

  @override void ngOnDestroy() {
    super.ngOnDestroy();

    _beforeDestroyChildSubscription?.cancel();
    _toggleStateSubscription?.cancel();

    _beforeDestroyChild$ctrl.close();
    _isOpen$ctrl.close();
    _toggle$ctrl.close();
  }

  @override Stream<bool> ngBeforeDestroyChild([List<dynamic> args]) async* {
    final Completer<bool> completer = new Completer<bool>();

    beforeDestroyChild.add(true);

    beforeDestroyChild.stream
        .take(1)
        .listen((_) {
      completer.complete(true);
    });

    await completer.future;

    yield true;
  }

  //-----------------------------
  // private methods
  //-----------------------------

  void _initStreams() {
    _toggleStateSubscription = rx.observable(_isOpen$ctrl.stream.distinct())
      .startWith(<bool>[false])
      .flatMapLatest((bool isOpen) => rx.observable(_toggle$ctrl.stream)
        .debounce(const Duration(milliseconds: 100))
        .map((_) => isOpen)
        .take(1))
      .listen(_toggleState);
  }

  void _toggleState(bool newIsOpenState) {
    if (!newIsOpenState) {
      _isOpen$ctrl.add(true);

      this.isOpen = true;

      changeDetector.markForCheck();
    } else {
      _beforeDestroyChildSubscription?.cancel();

      _beforeDestroyChildSubscription = ngBeforeDestroyChild()
          .take(1)
          .listen((_) {
        _isOpen$ctrl.add(false);

        this.isOpen = false;

        changeDetector.markForCheck();
      });
    }
  }

  //-----------------------------
  // template methods
  //-----------------------------

  void toggle() => _toggle$ctrl.add(true);
}