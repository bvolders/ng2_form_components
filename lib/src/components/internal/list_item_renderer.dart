library ng2_form_components.components.list_item_renderer;

import 'dart:async';
import 'dart:html';

import 'package:angular2/angular2.dart';
import 'package:angular2/src/core/linker/view_utils.dart';

import 'package:rxdart/rxdart.dart' as rx;
import 'package:tuple/tuple.dart';

import 'package:ng2_form_components/src/components/internal/form_component.dart' show LabelHandler;
import 'package:ng2_form_components/src/components/list_item.dart' show ListItem;

import 'package:ng2_form_components/src/infrastructure/list_renderer_service.dart' show ListRendererService;

import 'package:ng2_form_components/src/components/internal/form_component.dart';

import 'package:dnd/dnd.dart';

typedef bool IsSelectedHandler (ListItem<Comparable<dynamic>> listItem);
typedef String GetHierarchyOffsetHandler(ListItem<Comparable<dynamic>> listItem);
typedef void ListDragDropHandler(ListItem<Comparable<dynamic>> dragListItem, ListItem<Comparable<dynamic>> dropListItem, int offset);
typedef ListDragDropHandlerType DragDropTypeHandler(ListItem<Comparable<dynamic>> listItem);

enum ListDragDropHandlerType {
  SORT,
  SWAP,
  ALL
}

@Component(
    selector: 'list-item-renderer',
    template: '''
      <div #dragdropAbove *ngIf="showSortingAreas()" [ngClass]="dragdropAboveClass"></div>
      <div #renderType></div>
      <div #dragdropBelow *ngIf="showSortingAreas()" [ngClass]="dragdropBelowClass"></div>
    ''',
    providers: const <Type>[ViewUtils]
)
class ListItemRenderer<T extends Comparable<dynamic>> implements OnDestroy, OnInit, OnChanges {

  @ViewChild('renderType', read: ViewContainerRef) ViewContainerRef renderTypeTarget;
  @ViewChild('dragdropAbove', read: ViewContainerRef) ViewContainerRef dragdropAbove;
  @ViewChild('dragdropBelow', read: ViewContainerRef) ViewContainerRef dragdropBelow;

  //-----------------------------
  // input
  //-----------------------------

  @Input() ListRendererService listRendererService;
  @Input() int index;
  @Input() LabelHandler labelHandler;
  @Input() ListDragDropHandler dragDropHandler;
  @Input() DragDropTypeHandler dragDropTypeHandler;
  @Input() ListItem<T> listItem;
  @Input() IsSelectedHandler isSelected;
  @Input() GetHierarchyOffsetHandler getHierarchyOffset;
  @Input() ResolveRendererHandler resolveRendererHandler;

  //-----------------------------
  // public properties
  //-----------------------------

  final DynamicComponentLoader dynamicComponentLoader;
  final ElementRef elementRef;
  final ChangeDetectorRef changeDetector;
  final ViewUtils viewUtils;
  final Injector injector;

  final StreamController<List<bool>> _dragDropDisplay$ctrl = new StreamController<List<bool>>.broadcast();
  final StreamController<ComponentRef> _componentRef$ctrl = new StreamController<ComponentRef>.broadcast();
  final StreamController<ListDragDropHandler> _dragDropHandler$ctrl = new StreamController<ListDragDropHandler>.broadcast();
  final StreamController<DragDropTypeHandler> _dragDropTypeHandler$ctrl = new StreamController<DragDropTypeHandler>.broadcast();

  StreamSubscription<DropzoneEvent> _dropSubscription;
  StreamSubscription<List<bool>> _dropZoneLeaveSubscription;
  StreamSubscription<Tuple2<Element, List<bool>>> _shiftSubscription;
  StreamSubscription<MouseEvent> _showHooksSubscription;
  StreamSubscription<List<bool>> _dragDropDisplaySubscription;
  StreamSubscription<Tuple3<ComponentRef, ListDragDropHandler, DragDropTypeHandler>> _setupDragDropSubscription;

  Map<String, bool> dragdropAboveClass = const <String, bool>{'dnd-sort-handler': false}, dragdropBelowClass = const <String, bool>{'dnd-sort-handler': false};

  bool _isChildComponentInjected = false;

  //-----------------------------
  // constructor
  //-----------------------------

  ListItemRenderer(
    @Inject(Injector) this.injector,
    @Inject(DynamicComponentLoader) this.dynamicComponentLoader,
    @Inject(ElementRef) this.elementRef,
    @Inject(ViewUtils) this.viewUtils,
    @Inject(ChangeDetectorRef) this.changeDetector);

  //-----------------------------
  // ng2 life cycle
  //-----------------------------

  @override void ngOnChanges(Map<String, SimpleChange> changes) {
    if (changes.containsKey('dragDropHandler') && dragDropHandler != null) _dragDropHandler$ctrl.add(dragDropHandler);
    if (changes.containsKey('dragDropTypeHandler') && dragDropTypeHandler != null) _dragDropTypeHandler$ctrl.add(dragDropTypeHandler);
  }

  @override void ngOnDestroy() {
    if (dragDropHandler != null) {
      final List<Element> elements = <Element>[elementRef.nativeElement];

      if (dragdropAbove != null) elements.add(dragdropAbove.element.nativeElement);
      if (dragdropBelow != null) elements.add(dragdropBelow.element.nativeElement);

      elements.forEach((Element element) {
        if (listRendererService.dragDropElements.where((Map<Element, ListItem<Comparable<dynamic>>> valuePair) => valuePair.containsKey(element)).isNotEmpty)
          listRendererService.dragDropElements.removeWhere((Map<Element, ListItem<Comparable<dynamic>>> valuePair) => valuePair.containsKey(element));
      });
    }

    _dropSubscription?.cancel();
    _shiftSubscription?.cancel();
    _dropZoneLeaveSubscription?.cancel();
    _showHooksSubscription?.cancel();
    _dragDropDisplaySubscription?.cancel();
    _setupDragDropSubscription?.cancel();

    _dragDropDisplay$ctrl.close();
    _componentRef$ctrl.close();
    _dragDropHandler$ctrl.close();
    _dragDropTypeHandler$ctrl.close();
  }

  @override void ngOnInit() => _injectChildComponent();

  void _injectChildComponent() {
    if (_isChildComponentInjected || resolveRendererHandler == null || renderTypeTarget == null) return;

    _isChildComponentInjected = true;

    final Type resolvedRendererType = resolveRendererHandler(0, listItem);

    if (resolvedRendererType == null) throw new ArgumentError('Unable to resolve renderer for list item: ${listItem.runtimeType}');

    _setupDragDropSubscription = new rx.Observable<Tuple3<ComponentRef, ListDragDropHandler, DragDropTypeHandler>>.combineLatest(<Stream<dynamic>>[
      _componentRef$ctrl.stream,
      rx.observable(_dragDropHandler$ctrl.stream)
        .startWith(<ListDragDropHandler>[dragDropHandler]),
      rx.observable(_dragDropTypeHandler$ctrl.stream)
        .startWith(<DragDropTypeHandler>[dragDropTypeHandler])
    ], (ComponentRef ref, ListDragDropHandler dragDropHandler, DragDropTypeHandler dragDropTypeHandler) => new Tuple3<ComponentRef, ListDragDropHandler, DragDropTypeHandler>(ref, dragDropHandler, dragDropTypeHandler))
      .where((Tuple3<ComponentRef, ListDragDropHandler, DragDropTypeHandler> tuple) => tuple.item1 != null && tuple.item2 != null && tuple.item3 != null)
      .take(1)
      .listen(_setupDragDrop);

    dynamicComponentLoader.loadNextToLocation(resolvedRendererType, renderTypeTarget, ReflectiveInjector.fromResolvedProviders(ReflectiveInjector.resolve(<Provider>[
      new Provider(ListRendererService, useValue: listRendererService),
      new Provider(ListItem, useValue: listItem),
      new Provider(IsSelectedHandler, useValue: isSelected),
      new Provider(GetHierarchyOffsetHandler, useValue: getHierarchyOffset),
      new Provider(LabelHandler, useValue: labelHandler),
      new Provider('list-item-index', useValue: index),
      new Provider(ViewUtils, useValue: viewUtils)
    ]), injector)).then((ComponentRef ref) {
      _componentRef$ctrl.add(ref);

      changeDetector.markForCheck();
    });
  }

  void _setupDragDropSwap() {
    final Dropzone dropZone = new Dropzone(elementRef.nativeElement);

    _dropSubscription = dropZone.onDrop
      .listen((DropzoneEvent event) {
        final Map<Element, ListItem<Comparable<dynamic>>> pair = listRendererService.dragDropElements
          .firstWhere((Map<Element, ListItem<Comparable<dynamic>>> valuePair) => valuePair.containsKey(event.draggableElement), orElse: () => null);
        final ListItem<Comparable<dynamic>> draggableListItem = pair[event.draggableElement];

        if (draggableListItem.compareTo(listItem) != 0) dragDropHandler(draggableListItem, listItem, 0);
    });
  }

  void _setupDragDropSort(Element rendererElement) {
    final Element element = elementRef.nativeElement;
    final Element contentElement = rendererElement.children.first;
    final Dropzone dropZone = new Dropzone(element, overClass: 'dnd-owning-object');

    _shiftSubscription = rx.observable(_dragDropDisplay$ctrl.stream)
      .flatMapLatest((List<bool> indices) => rx.observable(dropZone.onDrop)
        .map((DropzoneEvent event) => new Tuple2<Element, List<bool>>(event.draggableElement, indices)))
      .listen((Tuple2<Element, List<bool>> tuple) {
        final Map<Element, ListItem<Comparable<dynamic>>> pair = listRendererService.dragDropElements
          .firstWhere((Map<Element, ListItem<Comparable<dynamic>>> valuePair) => valuePair.containsKey(tuple.item1), orElse: () => null);
        final ListItem<Comparable<dynamic>> draggableListItem = pair[tuple.item1];

        if (draggableListItem.compareTo(listItem) != 0) dragDropHandler(pair[tuple.item1], listItem, tuple.item2.first ? -1 : tuple.item2.last ? 1 : 0);
      });

    _dropZoneLeaveSubscription = element.onMouseLeave
      .where((_) => dragdropAboveClass.values.contains(true) || dragdropBelowClass.values.contains(true))
      .map((_) => const <bool>[false, false])
      .listen(_dragDropDisplay$ctrl.add);

    _showHooksSubscription = rx.observable(dropZone.onDragEnter)
      .where((DropzoneEvent event) => event.draggableElement != element)
      .flatMapLatest((_) => rx.observable(contentElement.onMouseMove)
        .takeUntil(element.onMouseLeave))
      .listen((MouseEvent event) {
        if (event.offset.y < contentElement.client.height ~/ 2) _dragDropDisplay$ctrl.add(const <bool>[true, false]);
        else _dragDropDisplay$ctrl.add(const <bool>[false, true]);
      });

    _dragDropDisplaySubscription = rx.observable(_dragDropDisplay$ctrl.stream)
      .listen((List<bool> indices) {
        dragdropAboveClass = <String, bool>{'dnd-sort-handler': indices.first, 'dnd-sort-handler--out': !indices.first};
        dragdropBelowClass = <String, bool>{'dnd-sort-handler': indices.last, 'dnd-sort-handler--out': !indices.last};

        changeDetector.markForCheck();
      });
  }

  bool showSortingAreas() {
    if (dragDropTypeHandler != null) {
      final ListDragDropHandlerType type = dragDropTypeHandler(listItem);

      return type == ListDragDropHandlerType.ALL || type == ListDragDropHandlerType.SORT;
    }

    return false;
  }

  void _setupDragDrop(Tuple3<ComponentRef, ListDragDropHandler, DragDropTypeHandler> tuple) {
    (tuple.item1.location.nativeElement as Element).className = 'dnd--child';

    listRendererService.dragDropElements.add(<Element, ListItem<Comparable<dynamic>>>{elementRef.nativeElement: listItem});

    new Draggable(elementRef.nativeElement, verticalOnly: true);

    switch (tuple.item3(listItem)) {
      case ListDragDropHandlerType.SWAP:
        _setupDragDropSwap();

        break;
      case ListDragDropHandlerType.SORT:
        _setupDragDropSort(tuple.item1.location.nativeElement);

        break;
      case ListDragDropHandlerType.ALL:
        _setupDragDropSwap();
        _setupDragDropSort(tuple.item1.location.nativeElement);

        break;
    }
  }

}