library ng2_form_components.components.helpers.drag_drop;

import 'dart:async';
import 'dart:html';

import 'package:angular2/angular2.dart';
import 'package:rxdart/rxdart.dart' as rx;
import 'package:tuple/tuple.dart';
import 'package:dorm/dorm.dart';

import 'package:ng2_form_components/src/components/list_item.dart';
import 'package:ng2_form_components/src/components/internal/list_item_renderer.dart';

import 'package:ng2_form_components/src/infrastructure/drag_drop_service.dart';

@Directive(
  selector: '[ngDragDrop]'
)
class DragDrop implements OnDestroy {

  static const num _OFFSET = 11;

  @Input() set ngDragDropHandler(ListDragDropHandler handler) => _handler$ctrl.add(handler);
  @Input() set ngDragDrop(ListItem<Comparable<dynamic>> listItem) => _listItem$ctrl.add(listItem);

  @Output() Stream<DropResult> get onDrop => _onDrop$ctrl.stream;

  final Renderer renderer;
  final ElementRef elementRef;
  final ChangeDetectorRef changeDetector;
  final DragDropService dragDropService;

  rx.Observable<bool> dragDetection$;
  rx.Observable<bool> dragOver$;
  rx.Observable<bool> dragOut$;

  final StreamController<ListItem<Comparable<dynamic>>> _listItem$ctrl = new StreamController<ListItem<Comparable<dynamic>>>();
  final StreamController<ListDragDropHandler> _handler$ctrl = new StreamController<ListDragDropHandler>();
  final StreamController<DropResult> _onDrop$ctrl = new StreamController<DropResult>.broadcast();

  StreamSubscription<bool> _initSubscription;
  StreamSubscription<MouseEvent> _dropHandlerSubscription;
  StreamSubscription<MouseEvent> _sortHandlerSubscription;
  StreamSubscription<MouseEvent> _dragStartSubscription;
  StreamSubscription<MouseEvent> _dragEndSubscription;
  StreamSubscription<bool> _dragOutSubscription;
  StreamSubscription<ListItem<Comparable<dynamic>>> _swapDropSubscription;
  StreamSubscription<Tuple2<ListItem<Comparable<dynamic>>, int>> _sortDropSubscription;

  SerializerJson<String, Map<String, dynamic>> serializer;
  bool _areStreamsSet = false;
  num heightOnDragEnter = 0;

  DragDrop(
    @Inject(Renderer) this.renderer,
    @Inject(ElementRef) this.elementRef,
    @Inject(ChangeDetectorRef) this.changeDetector,
    @Inject(DragDropService) this.dragDropService) {
      _initStreams();
    }

  @override void ngOnDestroy() {
    _initSubscription?.cancel();
    _dropHandlerSubscription?.cancel();
    _sortHandlerSubscription?.cancel();
    _dragStartSubscription?.cancel();
    _dragEndSubscription?.cancel();
    _dragOutSubscription?.cancel();
    _swapDropSubscription?.cancel();
    _sortDropSubscription?.cancel();

    _listItem$ctrl.close();
    _handler$ctrl.close();
    _onDrop$ctrl.close();
  }

  void _initStreams() {
    _initSubscription = new rx.Observable<bool>.combineLatest(<Stream<dynamic>>[
      rx.observable(_listItem$ctrl.stream)
        .startWith(<ListItem<Comparable<dynamic>>>[null]),
      rx.observable(_handler$ctrl.stream)
        .startWith(<ListDragDropHandler>[null])
    ], (ListItem<Comparable<dynamic>> listItem, ListDragDropHandler handler) {
      if (listItem != null && handler != null) {
        final ListDragDropHandlerType type = dragDropService.typeHandler(listItem);

        if (type != ListDragDropHandlerType.NONE) _setupAsDragDrop(listItem);

        if (type == ListDragDropHandlerType.SORT || type == ListDragDropHandlerType.ALL) _createSortHandlers(listItem, handler);
        if (type == ListDragDropHandlerType.SWAP || type == ListDragDropHandlerType.ALL) _createDropHandler(listItem, handler);
      }

      return true;
    })
      .listen((_) {});
  }

  void _setupAsDragDrop(ListItem<Comparable<dynamic>> listItem) {
    if (_areStreamsSet) return;

    final Element element = elementRef.nativeElement;

    _areStreamsSet = true;

    dragDetection$ = new rx.Observable<int>.merge(<Stream<int>>[
      rx.observable(element.onDragEnter)
        .tap((_) {
          heightOnDragEnter = element.client.height;
        })
        .map((_) => 1),
      element.onDragLeave
        .map((_) => -1),
      element.onDrop
        .map((_) => -1)
    ], asBroadcastStream: true)
      .scan((int acc, int value, _) => acc + value, 0)
      .map((int result) => result > 0)
      .distinct();

    dragOver$ = dragDetection$
      .where((bool value) => value);

    dragOut$ = dragDetection$
      .where((bool value) => !value)
      .map((_) => true);

    serializer = new SerializerJson<String, Map<String, dynamic>>()
      ..asDetached = true
      ..outgoing(const [])
      ..addRule(
          DateTime,
          (int value) => (value != null) ? new DateTime.fromMillisecondsSinceEpoch(value, isUtc:true) : null,
          (DateTime value) => value?.millisecondsSinceEpoch
      );

    _dragStartSubscription = element.onDragStart
      .listen((MouseEvent event) {
        event.dataTransfer.effectAllowed = 'move';
        event.dataTransfer.setData('text/plain', serializer.outgoing(<Entity>[listItem]));

        renderer.setElementClass(element, 'ngDragDrop--active', true);
      });

    _dragEndSubscription = element.onDragEnd
      .listen((MouseEvent event) {
        renderer.setElementClass(element, 'ngDragDrop--active', false);
      });

    _dragOutSubscription = dragOut$
      .listen(_removeAllStyles);
  }

  void _createDropHandler(ListItem<Comparable<dynamic>> listItem, ListDragDropHandler handler) {
    final Element element = elementRef.nativeElement;

    element.setAttribute('draggable', 'true');

    _sortHandlerSubscription = new rx.Observable<MouseEvent>.merge(<Stream<MouseEvent>>[element.onDragOver, element.onDragLeave])
      .listen((MouseEvent event) {
        event.preventDefault();

        renderer.setElementClass(element, dragDropService.resolveDropClassName(listItem), _isWithinDropBounds(event.client.y));
      });

    _swapDropSubscription = element.onDrop
      .map(_dataTransferToListItem)
      .listen((ListItem<Comparable<dynamic>> droppedListItem) {
        if (droppedListItem.compareTo(listItem) != 0) {
          handler(droppedListItem, listItem, 0);

          _onDrop$ctrl.add(new DropResult(0, listItem));
        }

        _removeAllStyles(null);
      });
  }

  void _createSortHandlers(ListItem<Comparable<dynamic>> listItem, ListDragDropHandler handler) {
    final Element element = elementRef.nativeElement;

    element.setAttribute('draggable', 'true');

    _dropHandlerSubscription = element.onDragOver
      .listen((MouseEvent event) {
        event.preventDefault();

        renderer.setElementClass(element, 'ngDragDrop--sort-handler--above', _isSortAbove(event.client.y));
        renderer.setElementClass(element, 'ngDragDrop--sort-handler--below', _isSortBelow(event.client.y));
      });

    _sortDropSubscription = element.onDrop
      .map((MouseEvent event) => new Tuple2<ListItem<Comparable<dynamic>>, int>(_dataTransferToListItem(event), _getSortOffset(event)))
      .listen((Tuple2<ListItem<Comparable<dynamic>>, int> tuple) {
        if (tuple.item1.compareTo(listItem) != 0) {
          handler(tuple.item1, listItem, tuple.item2);

          _onDrop$ctrl.add(new DropResult(tuple.item2, tuple.item2 == 0 ? listItem : tuple.item1));
        }

        _removeAllStyles(null);
      });
  }

  int _getSortOffset(MouseEvent event) {
    if (_isSortAbove(event.client.y)) return -1;
    else if (_isSortBelow(event.client.y)) return 1;

    return 0;
  }

  ListItem<Comparable<dynamic>> _dataTransferToListItem(MouseEvent event) {
    final String transferDataEncoded = event.dataTransfer.getData('text/plain');

    if (transferDataEncoded.isEmpty) return null;

    final EntityFactory<Entity> factory = new EntityFactory<Entity>();
    final List<dynamic> result = factory.spawn(serializer.incoming(transferDataEncoded), serializer,
        (Entity serverEntity, Entity clientEntity) => ConflictManager.AcceptClient);

    return result.first as ListItem<Comparable<dynamic>>;
  }

  void _removeAllStyles(dynamic _) {
    final Element element = elementRef.nativeElement;

    renderer.setElementClass(element, 'ngDragDrop--drop-inside', false);
    renderer.setElementClass(element, 'ngDragDrop--sort-handler--above', false);
    renderer.setElementClass(element, 'ngDragDrop--sort-handler--below', false);
  }

  num _getActualOffsetY(Element element, num clientY) {
    return clientY - element.getBoundingClientRect().top;
  }

  bool _isWithinDropBounds(num clientY) {
    final num y = _getActualOffsetY(elementRef.nativeElement, clientY);

    return (y > _OFFSET && y < heightOnDragEnter - _OFFSET);
  }

  bool _isSortAbove(num clientY) => _getActualOffsetY(elementRef.nativeElement, clientY) <= _OFFSET;

  bool _isSortBelow(num clientY) => _getActualOffsetY(elementRef.nativeElement, clientY) >= heightOnDragEnter - _OFFSET;
}

class DropResult {

  final int type;
  final ListItem<Comparable<dynamic>> listItem;

  DropResult(this.type, this.listItem);

}