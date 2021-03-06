library ng2_form_components.components.hierarchy;

import 'dart:async';
import 'dart:html';

import 'package:rxdart/rxdart.dart' as rx show Observable, observable;
import 'package:dorm/dorm.dart' show Entity;
import 'package:tuple/tuple.dart' show Tuple2;
import 'package:angular2/angular2.dart';

import 'package:ng2_form_components/src/components/interfaces/before_destroy_child.dart' show BeforeDestroyChild;

import 'package:ng2_form_components/src/components/internal/form_component.dart' show LabelHandler;
import 'package:ng2_form_components/src/components/internal/list_item_renderer.dart' show ListItemRenderer, ListDragDropHandler;
import 'package:ng2_form_components/src/components/internal/drag_drop_list_item_renderer.dart' show DragDropListItemRenderer;

import 'package:ng2_form_components/src/components/list_renderer.dart' show ListRenderer, ClearSelectionWhereHandler, NgForTracker;
import 'package:ng2_form_components/src/components/list_item.dart' show ListItem;

import 'package:ng2_form_components/src/components/animation/hierarchy_animation.dart' show HierarchyAnimation;

import 'package:ng2_form_components/src/components/item_renderers/default_hierarchy_list_item_renderer.dart' show DefaultHierarchyListItemRenderer;

import 'package:ng2_form_components/src/infrastructure/list_renderer_service.dart' show ItemRendererEvent, ListRendererEvent, ListRendererService;

import 'package:ng2_state/ng2_state.dart' show State, SerializableTuple1, SerializableTuple3, StatePhase, StateService;

import 'package:ng2_form_components/src/components/internal/form_component.dart' show ResolveChildrenHandler, ResolveRendererHandler;

typedef bool ShouldOpenDiffer(ListItem<Comparable<dynamic>> itemA, ListItem<Comparable<dynamic>> itemB);

@Component(
    selector: 'hierarchy',
    templateUrl: 'hierarchy.html',
    directives: const <Type>[State, Hierarchy, HierarchyAnimation, ListItemRenderer, DragDropListItemRenderer],
    providers: const <Type>[StateService],
    changeDetection: ChangeDetectionStrategy.OnPush,
    preserveWhitespace: false
)
class Hierarchy<T extends Comparable<dynamic>> extends ListRenderer<T> implements OnChanges, OnDestroy, AfterViewInit, BeforeDestroyChild {

  @ViewChild('subHierarchy') Hierarchy<Comparable<dynamic>> subHierarchy;

  @override @ViewChild('scrollPane')set scrollPane(ElementRef value) {
    super.scrollPane = value;
  }

  //-----------------------------
  // input
  //-----------------------------

  @override @Input() set labelHandler(LabelHandler value) {
    super.labelHandler = value;
  }

  @override @Input() set dragDropHandler(ListDragDropHandler value) {
    super.dragDropHandler = value;
  }

  @override @Input() set dataProvider(List<ListItem<T>> value) {
    forceAnimateOnOpen = false;

    _cleanupOpenMap();

    super.dataProvider = value;
  }

  @override @Input() set selectedItems(List<ListItem<T>> value) {
    super.selectedItems = value;
  }

  @override @Input() set allowMultiSelection(bool value) {
    super.allowMultiSelection = value;
  }

  @override bool get moveSelectionOnTop => false;

  @override @Input() set childOffset(int value) {
    super.childOffset = value;
  }

  @override @Input() set rendererEvents(List<ListRendererEvent<dynamic, Comparable<dynamic>>> value) {
    super.rendererEvents = value;
  }

  @override @Input() set pageOffset(int value) {
    super.pageOffset = value;
  }

  @override @Input() set listRendererService(ListRendererService value) {
    super.listRendererService = value;

    _listRendererService$ctrl.add(value);

    value?.triggerEvent(new ItemRendererEvent<Hierarchy<Comparable<dynamic>>, T>('childRegistry', null, this));
  }

  int _level = 0;
  int get level => _level;
  @Input() set level(int value) {
    _level = value;
  }

  bool _autoOpenChildren = false;
  bool get autoOpenChildren => _autoOpenChildren;
  @Input() set autoOpenChildren(bool value) {
    _autoOpenChildren = value;
  }

  List<ListItem<Comparable<dynamic>>> _hierarchySelectedItems;
  List<ListItem<Comparable<dynamic>>> get hierarchySelectedItems => _hierarchySelectedItems;
  @Input() set hierarchySelectedItems(List<ListItem<Comparable<dynamic>>> value) {
    _hierarchySelectedItems = value;
  }

  List<int> _levelsThatBreak = const [];
  List<int> get levelsThatBreak => _levelsThatBreak;
  @Input() set levelsThatBreak(List<int> value) {
    _levelsThatBreak = value;
  }

  @override @Input() set ngForTracker(NgForTracker value) {
    super.ngForTracker = value;
  }

  ResolveChildrenHandler _resolveChildrenHandler;
  ResolveChildrenHandler get resolveChildrenHandler => _resolveChildrenHandler;
  @Input() set resolveChildrenHandler(ResolveChildrenHandler value) {
    _resolveChildrenHandler = value;
  }

  bool _allowToggle = false;
  bool get allowToggle => _allowToggle;
  @Input() set allowToggle(bool value) {
    if (_allowToggle != value) {
      _allowToggle = value;

      changeDetector.markForCheck();
    }
  }

  ShouldOpenDiffer _shouldOpenDiffer = (ListItem<Comparable<dynamic>> itemA, ListItem<Comparable<dynamic>> itemB) => itemA.compareTo(itemB) == 0;
  ShouldOpenDiffer get shouldOpenDiffer => _shouldOpenDiffer;
  @Input() set shouldOpenDiffer(ShouldOpenDiffer value) {
    _shouldOpenDiffer = value;
  }

  @override @Input() set resolveRendererHandler(ResolveRendererHandler value) {
    super.resolveRendererHandler = value;
  }

  //-----------------------------
  // output
  //-----------------------------

  @override @Output() rx.Observable<List<ListItem<T>>> get selectedItemsChanged => rx.observable(_selection$) as rx.Observable<List<ListItem<T>>>;
  @override @Output() Stream<bool> get requestClose => super.requestClose;
  @override @Output() Stream<bool> get scrolledToBottom => super.scrolledToBottom;
  @override @Output() Stream<ItemRendererEvent<dynamic, Comparable<dynamic>>> get itemRendererEvent => super.itemRendererEvent;

  @override StreamController<int> get beforeDestroyChild => _beforeDestroyChild$ctrl;

  //-----------------------------
  // private properties
  //-----------------------------

  final Map<ListItem<T>, List<ListItem<T>>> _resolvedChildren = <ListItem<T>, List<ListItem<T>>>{};

  final StreamController<Tuple2<Hierarchy<Comparable<dynamic>>, bool>> _childHierarchies$ctrl = new StreamController<Tuple2<Hierarchy<Comparable<dynamic>>, bool>>.broadcast();
  final StreamController<ClearSelectionWhereHandler> _clearChildHierarchies$ctrl = new StreamController<ClearSelectionWhereHandler>.broadcast();
  final StreamController<List<Hierarchy<Comparable<dynamic>>>> _childHierarchyList$ctrl = new StreamController<List<Hierarchy<Comparable<dynamic>>>>.broadcast();
  final StreamController<Map<Hierarchy<Comparable<dynamic>>, List<ListItem<T>>>> _selection$Ctrl = new StreamController<Map<Hierarchy<Comparable<dynamic>>, List<ListItem<T>>>>.broadcast();
  final StreamController<List<ListItem<T>>> _openListItems$Ctrl = new StreamController<List<ListItem<T>>>.broadcast();
  final StreamController<int> _beforeDestroyChild$ctrl = new StreamController<int>.broadcast();
  final StreamController<bool> _domModified$ctrl = new StreamController<bool>.broadcast();
  final StreamController<ListRendererService> _listRendererService$ctrl = new StreamController<ListRendererService>();

  Map<ListItem<T>, bool> _isOpenMap = <ListItem<T>, bool>{};

  StreamSubscription<bool> _windowMutationListener;
  StreamSubscription<ItemRendererEvent<dynamic, Comparable<dynamic>>> _eventSubscription;
  StreamSubscription<Tuple2<List<Hierarchy<Comparable<dynamic>>>, ClearSelectionWhereHandler>> _clearChildHierarchiesSubscription;
  StreamSubscription<Tuple2<Hierarchy<Comparable<dynamic>>, List<Hierarchy<Comparable<dynamic>>>>> _registerChildHierarchySubscription;
  StreamSubscription<Map<Hierarchy<Comparable<dynamic>>, List<ListItem<T>>>> _selectionBuilderSubscription;
  StreamSubscription<Map<ListItem<T>, bool>> _beforeDestroyChildSubscription;
  StreamSubscription<int> _onBeforeDestroyChildSubscription;

  Stream<List<ListItem<Comparable<dynamic>>>> _selection$;

  bool forceAnimateOnOpen = false;

  List<ListItem<T>> _receivedSelection;

  //-----------------------------
  // constructor
  //-----------------------------

  Hierarchy(
    @Inject(ElementRef) ElementRef element,
    @Inject(ChangeDetectorRef) ChangeDetectorRef changeDetector,
    @Inject(StateService) StateService stateService) : super(element, changeDetector, stateService) {
      super.resolveRendererHandler = (int level, [_]) => DefaultHierarchyListItemRenderer;

      _initStreams();
    }

  //-----------------------------
  // ng2 life cycle
  //-----------------------------

  @override Stream<Entity> provideState() {
    return new rx.Observable<SerializableTuple3<int, List<ListItem<T>>, List<ListItem<T>>>>.combineLatest(<Stream<dynamic>>[
      rx.observable(super.provideState()).startWith(<SerializableTuple1<int>>[new SerializableTuple1<int>()..item1 = 0]),
      internalSelectedItemsChanged.startWith(const [const []]),
      rx.observable(_openListItems$Ctrl.stream)
        .where((_) => !autoOpenChildren)
        .startWith(const [const []])
    ], (SerializableTuple1<int> scrollPosition, List<ListItem<T>> selectedItems, List<ListItem<T>> openItems) =>
      new SerializableTuple3<int, List<ListItem<T>>, List<ListItem<T>>>()
        ..item1 = scrollPosition.item1
        ..item2 = selectedItems
        ..item3 = openItems, asBroadcastStream: true);
  }

  @override void ngAfterViewInit() {
    super.ngAfterViewInit();

    if (hierarchySelectedItems == null || hierarchySelectedItems.isEmpty) _processIncomingSelectedState(_receivedSelection);

    hierarchySelectedItems = null;
  }

  @override void receiveState(Entity entity, StatePhase phase) {
    final SerializableTuple3<int, List<Entity>, List<Entity>> tuple = entity as SerializableTuple3<int, List<Entity>, List<Entity>>;
    final List<ListItem<T>> listCast = <ListItem<T>>[];
    final List<ListItem<T>> listCast2 = <ListItem<T>>[];

    tuple.item2.forEach((Entity entity) => listCast.add(entity as ListItem<T>));

    super.receiveState(new SerializableTuple1<int>()
      ..item1 = tuple.item1, phase);

    _receivedSelection = listCast;

    tuple.item3.forEach((Entity entity) {
      final ListItem<T> listItem = entity as ListItem<T>;
      _isOpenMap[listItem] = true;

      listCast2.add(listItem);
    });

    _openListItems$Ctrl.add(listCast2);

    listRendererService.notifyIsOpenChange();

    if (tuple.item3.isNotEmpty) changeDetector.markForCheck();
  }

  @override void ngOnChanges(Map<String, SimpleChange> changes) {
    super.ngOnChanges(changes);

    if (changes.containsKey('hierarchySelectedItems') && hierarchySelectedItems != null && hierarchySelectedItems.isNotEmpty) {
      hierarchySelectedItems.forEach((ListItem<Comparable<dynamic>> listItem) {
        listRendererService.rendererSelection$
          .take(1)
          .map((_) => new ItemRendererEvent<bool, T>('selection', listItem as ListItem<T>, true))
          .listen(listRendererService.triggerEvent);

        listRendererService.triggerSelection(listItem);
      });

      //changeDetector.markForCheck();
    }
  }

  @override Stream<int> ngBeforeDestroyChild([List<dynamic> args]) async* {
    final List<int> argsCast = args as List<int>;
    final Completer<int> completer = new Completer<int>();

    beforeDestroyChild.add(argsCast.first);

    _onBeforeDestroyChildSubscription = new rx.Observable<int>.merge(<Stream<int>>[
      beforeDestroyChild.stream
        .where((int index) => index == argsCast.first),
      onDestroy
        .map((_) => 0)
    ])
      .take(1)
      .listen((_) => completer.complete(argsCast.first));

    await completer.future;

    yield args.first;
  }

  @override void ngOnDestroy() {
    super.ngOnDestroy();

    _windowMutationListener?.cancel();
    _eventSubscription?.cancel();
    _clearChildHierarchiesSubscription?.cancel();
    _registerChildHierarchySubscription?.cancel();
    _selectionBuilderSubscription?.cancel();
    _beforeDestroyChildSubscription?.cancel();
    _onBeforeDestroyChildSubscription?.cancel();

    _childHierarchies$ctrl.close();
    _clearChildHierarchies$ctrl.close();
    _childHierarchyList$ctrl.close();
    _selection$Ctrl.close();
    _openListItems$Ctrl.close();
    _beforeDestroyChild$ctrl.close();
    _domModified$ctrl.close();
    _listRendererService$ctrl.close();
  }

  //-----------------------------
  // private methods
  //-----------------------------

  void _initStreams() {
    _windowMutationListener = domChange$
      .listen(_handleDomChange);

    _eventSubscription = rx.observable(_listRendererService$ctrl.stream)
      .flatMapLatest((ListRendererService service) => service.event$)
      .listen(_handleItemRendererEvent);

    _clearChildHierarchiesSubscription = new rx.Observable<Tuple2<List<Hierarchy<Comparable<dynamic>>>, ClearSelectionWhereHandler>>.combineLatest(<Stream<dynamic>>[
      _childHierarchyList$ctrl.stream,
      _clearChildHierarchies$ctrl.stream
    ], (List<Hierarchy<Comparable<dynamic>>> childHierarchies, ClearSelectionWhereHandler handler) => new Tuple2<List<Hierarchy<Comparable<dynamic>>>, ClearSelectionWhereHandler>(childHierarchies, handler))
      .listen((Tuple2<List<Hierarchy<Comparable<dynamic>>>, ClearSelectionWhereHandler> tuple) => tuple.item1.forEach((Hierarchy<Comparable<dynamic>> childHierarchy) => childHierarchy.clearSelection(tuple.item2)));

    _registerChildHierarchySubscription = new rx.Observable<Tuple2<Tuple2<Hierarchy<Comparable<dynamic>>, bool>, List<Hierarchy<Comparable<dynamic>>>>>.zip(<Stream<dynamic>>[
      _childHierarchies$ctrl.stream,
      _childHierarchyList$ctrl.stream
    ], (Tuple2<Hierarchy<Comparable<dynamic>>, bool> childHierarchy, List<Hierarchy<Comparable<dynamic>>> hierarchies) {
      final List<Hierarchy<Comparable<dynamic>>> clone = hierarchies.toList();

      if (childHierarchy.item2) clone.add(childHierarchy.item1);
      else clone.remove(childHierarchy.item1);

      return new Tuple2<Tuple2<Hierarchy<Comparable<dynamic>>, bool>, List<Hierarchy<Comparable<dynamic>>>>(childHierarchy, new List<Hierarchy<Comparable<dynamic>>>.unmodifiable(clone));
    })
      .tap((Tuple2<Tuple2<Hierarchy<Comparable<dynamic>>, bool>, List<Hierarchy<Comparable<dynamic>>>> tuple) => _childHierarchyList$ctrl.add(tuple.item2))
      .where((Tuple2<Tuple2<Hierarchy<Comparable<dynamic>>, bool>, List<Hierarchy<Comparable<dynamic>>>> tuple) => tuple.item1.item2)
      .map((Tuple2<Tuple2<Hierarchy<Comparable<dynamic>>, bool>, List<Hierarchy<Comparable<dynamic>>>> tuple) => new Tuple2<Hierarchy<Comparable<dynamic>>, List<Hierarchy<Comparable<dynamic>>>>(tuple.item1.item1, tuple.item2))
      .flatMap((Tuple2<Hierarchy<Comparable<dynamic>>, List<Hierarchy<Comparable<dynamic>>>> tuple) => tuple.item1.onDestroy.take(1).map((_) => tuple))
      .listen((Tuple2<Hierarchy<Comparable<dynamic>>, List<Hierarchy<Comparable<dynamic>>>> tuple) => _childHierarchies$ctrl.add(new Tuple2<Hierarchy<Comparable<dynamic>>, bool>(tuple.item1, false)));

    _selectionBuilderSubscription = new rx.Observable<Map<Hierarchy<Comparable<dynamic>>, List<ListItem<T>>>>.zip(<Stream<dynamic>>[
      rx.observable(_selection$Ctrl.stream).startWith(<Map<Hierarchy<Comparable<dynamic>>, List<ListItem<T>>>>[<Hierarchy<Comparable<dynamic>>, List<ListItem<T>>>{}]),
      rx.observable(_childHierarchyList$ctrl.stream)
        .flatMapLatest((List<Hierarchy<Comparable<dynamic>>> hierarchies) => new rx.Observable<dynamic>
          .merge((new List<Hierarchy<Comparable<dynamic>>>.from(hierarchies)..add(this))
          .map((Hierarchy<Comparable<dynamic>> hierarchy) => hierarchy.internalSelectedItemsChanged
            .map((List<ListItem<Comparable<dynamic>>> selectedItems) => new Tuple2<Hierarchy<Comparable<dynamic>>, List<ListItem<Comparable<dynamic>>>>(hierarchy, selectedItems)))))
    ], (Map<Hierarchy<Comparable<dynamic>>, List<ListItem<Comparable<dynamic>>>> selectedItems, Tuple2<Hierarchy<Comparable<dynamic>>, List<ListItem<Comparable<dynamic>>>> tuple) {
      if (tuple.item1.stateGroup != null && tuple.item1.stateGroup.isNotEmpty && tuple.item1.stateId != null && tuple.item1.stateId.isNotEmpty) {
        Hierarchy<Comparable<dynamic>> match;

        selectedItems.forEach((Hierarchy<Comparable<dynamic>> hierarchy, _) {
          if (hierarchy.stateGroup == tuple.item1.stateGroup && hierarchy.stateId == tuple.item1.stateId) match = hierarchy;
        });

        if (match != null && match != tuple.item1) selectedItems.remove(match);
      }

      selectedItems[tuple.item1] = tuple.item2;

      return selectedItems;
    })
      .where((_) => level == 0)
      .listen(_selection$Ctrl.add);

    _selection$ = _selection$Ctrl.stream
      .map((Map<Hierarchy<Comparable<dynamic>>, List<ListItem<Comparable<dynamic>>>> map) {
        final List<ListItem<Comparable<dynamic>>> fold = <ListItem<Comparable<dynamic>>>[];

        map.values.forEach(fold.addAll);

        return fold;
      });

    _childHierarchyList$ctrl.add(const []);
    _selection$Ctrl.add(<Hierarchy<Comparable<dynamic>>, List<ListItem<T>>>{});
    _listRendererService$ctrl.add(listRendererService);
  }

  void _handleItemRendererEvent(ItemRendererEvent<dynamic, Comparable<dynamic>> event) {
    if (event?.type == 'openRecursively') {
      final ItemRendererEvent<bool, Comparable<dynamic>> eventCast = event as ItemRendererEvent<bool, Comparable<dynamic>>;

      if (eventCast.data != null) {
        for (int i=0, len=dataProvider.length; i<len; i++) {
          ListItem<T> entry = dataProvider.elementAt(i);

          if (shouldOpenDiffer(eventCast.listItem, entry) && !isOpen(entry)) toggleChildren(entry, i);
        }
      }

      changeDetector.markForCheck();
    }
  }

  void _handleDomChange(bool _) {
    if (!_domModified$ctrl.isClosed) _domModified$ctrl.add(true);
  }

  void _processIncomingSelectedState(List<ListItem<T>> selectedItems) {
    if (selectedItems != null && selectedItems.isNotEmpty) {
      if (level == 0) selectedItems.forEach(handleSelection);
      else {
        new rx.Observable<dynamic>.merge(<Stream<dynamic>>[
          rx.observable(_domModified$ctrl.stream)
            .flatMapLatest((_) => new Stream<num>.fromFuture(window.animationFrame))
            .debounce(const Duration(milliseconds: 50)),
          new Stream<dynamic>.periodic(const Duration(milliseconds: 200))
        ])
          .take(1)
          .listen((_) {
            selectedItems.forEach((ListItem<Comparable<dynamic>> listItem) {
              rx.observable(listRendererService.rendererSelection$)
                  .take(1)
                  .map((_) => new ItemRendererEvent<bool, T>('selection', listItem, true))
                  .listen(handleRendererEvent);

              listRendererService.triggerSelection(listItem);
            });

            observer.disconnect();
          });
      }
    }
  }

  //-----------------------------
  // template methods
  //-----------------------------

  String getStateId(int index) {
    if (stateId != null) return '${stateId}_${level}_$index';

    return '${index}_$level';
  }

  bool resolveOpenState(ListItem<T> listItem, int index) {
    if (autoOpenChildren && !_isOpenMap.containsKey(listItem)) toggleChildren(listItem, index);

    return true;
  }

  @override bool isOpen(ListItem<T> listItem) {
    if (listItem.isAlwaysOpen) return true;

    bool result = false;

    for (int i=0, len=_isOpenMap.keys.length; i<len; i++) {
      ListItem<T> item = _isOpenMap.keys.elementAt(i);

      if (item.compareTo(listItem) == 0) {
        result = _isOpenMap[item];

        break;
      }
    }

    return result;
  }

  void maybeToggleChildren(ListItem<T> listItem, int index) {
    if (!allowToggle) toggleChildren(listItem, index);
  }

  void toggleChildren(ListItem<T> listItem, int index) {
    final List<ListItem<T>> openItems = <ListItem<T>>[];
    final Map<ListItem<T>, bool> clone = <ListItem<T>, bool>{};
    ListItem<T> match;

    forceAnimateOnOpen = true;

    _isOpenMap.forEach((ListItem<T> item, bool isOpen) => clone[item] = isOpen);

    clone.forEach((ListItem<T> item, _) {
      if (item.compareTo(listItem) == 0) match = item;
    });

    if (match != listItem) {
      clone.keys
        .where((ListItem<T> item) => item.compareTo(match) == 0)
        .toList(growable: false)
        .forEach(clone.remove);
    }

    ListItem<T> listItemMatch = clone.keys.firstWhere((ListItem<T> item) => item.compareTo(listItem) == 0, orElse: () => null);

    if (listItemMatch == null) clone[listItem] = (match == null);
    else clone[listItem] = !clone[listItem];

    clone.forEach((ListItem<T> listItem, bool isOpen) {
      if (isOpen) openItems.add(listItem);
    });

    listItemMatch = clone.keys.firstWhere((ListItem<T> item) => item.compareTo(listItem) == 0, orElse: () => null);

    if (listItemMatch != null && clone[listItem]) {
      _isOpenMap = clone;

      if (!_openListItems$Ctrl.isClosed) _openListItems$Ctrl.add(openItems);
    } else {
      _beforeDestroyChildSubscription?.cancel();

      _beforeDestroyChildSubscription = ngBeforeDestroyChild(<int>[index])
        .where((int i) => i == index)
        .take(1)
        .map((_) => clone)
        .listen((Map<ListItem<T>, bool> clone) {
          _isOpenMap = clone;

          if (!_openListItems$Ctrl.isClosed) _openListItems$Ctrl.add(openItems);

          changeDetector.markForCheck();
        });
    }

    listRendererService.notifyIsOpenChange();
  }

  void _cleanupOpenMap() {
    final List<ListItem<T>> removeList = <ListItem<T>>[];

    _isOpenMap.forEach((ListItem<T> item, bool isOpen) {
      if (!isOpen) removeList.add(item);
    });

    removeList.forEach(_isOpenMap.remove);

    listRendererService.notifyIsOpenChange();
  }

  List<ListItem<T>> resolveChildren(ListItem<T> listItem) {
    if (_resolvedChildren.containsKey(listItem)) return _resolvedChildren[listItem];

    final List<ListItem<T>> result = _resolvedChildren[listItem] = resolveChildrenHandler(level, listItem);

    return result;
  }

  void handleRendererEvent(ItemRendererEvent<dynamic, T> event) {
    if (event.type == 'childRegistry') _childHierarchies$ctrl.add(new Tuple2<Hierarchy<Comparable<dynamic>>, bool>(event.data as Hierarchy<Comparable<dynamic>>, true));

    if (!allowMultiSelection && event.type == 'selection') {
      clearSelection((ListItem<Comparable<dynamic>> listItem) => listItem != event.listItem);

      _clearChildHierarchies$ctrl.add((ListItem<Comparable<dynamic>> listItem) => listItem != event.listItem);
    }

    listRendererService.triggerEvent(event);
  }

  @override void handleSelection(ListItem<Comparable<dynamic>> listItem) {
    super.handleSelection(listItem);

    if (!allowMultiSelection) _clearChildHierarchies$ctrl.add((ListItem<Comparable<dynamic>> listItem) => true);
  }

  Type listItemRendererHandler(_, [ListItem<Comparable<dynamic>> listItem]) => resolveRendererHandler(level, listItem);
}