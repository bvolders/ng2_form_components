library ng2_form_components.components.html_text_transform_component;

import 'dart:async';
import 'dart:html';

import 'package:rxdart/rxdart.dart' as rx;
import 'package:tuple/tuple.dart';

import 'package:angular2/angular2.dart';
import 'package:dorm/dorm.dart' show Entity;

import 'package:ng2_state/ng2_state.dart' show StatefulComponent, SerializableTuple1, StatePhase;

import 'package:ng2_form_components/ng2_form_components.dart' show FormComponent;
import 'package:ng2_form_components/src/components/helpers/html_text_transformation.dart' show HTMLTextTransformation;
import 'package:ng2_form_components/src/components/helpers/html_transform.dart' show HtmlTransform;

@Component(
  selector: 'html-text-transform-component',
  templateUrl: 'html_text_transform_component.html',
  directives: const [NgClass],
  changeDetection: ChangeDetectionStrategy.OnPush
)
class HTMLTextTransformComponent extends FormComponent implements StatefulComponent, OnDestroy, AfterViewInit {

  final ElementRef element;
  final HtmlTransform transformer = new HtmlTransform();

  @ViewChild('content') ElementRef contentElement;

  //-----------------------------
  // input
  //-----------------------------

  @Input() String model;
  @Input() List<List<HTMLTextTransformation>> buttons;

  //-----------------------------
  // output
  //-----------------------------

  @Output() Stream<String> get transformation => _modelTransformation$ctrl.stream;
  @Output() Stream<bool> get hasSelectedRange => _hasSelectedRange$ctrl.stream;

  //-----------------------------
  // private properties
  //-----------------------------

  rx.Observable<Range> _range$;
  rx.Observable<Tuple2<Range, HTMLTextTransformation>> _rangeTransform$;
  StreamSubscription<Tuple2<Range, HTMLTextTransformation>> _range$subscription;
  StreamSubscription<bool> _hasRangeSubscription;

  final StreamController<HTMLTextTransformation> _transformation$ctrl = new StreamController<HTMLTextTransformation>.broadcast();
  final StreamController<String> _modelTransformation$ctrl = new StreamController<String>.broadcast();
  final StreamController<bool> _hasSelectedRange$ctrl = new StreamController<bool>();
  final StreamController<bool> _rangeTrigger$ctrl = new StreamController<bool>();

  bool _isDestroyCalled = false;

  //-----------------------------
  // Constructor
  //-----------------------------

  HTMLTextTransformComponent(@Inject(ElementRef) this.element, @Inject(ChangeDetectorRef) ChangeDetectorRef changeDetector) : super(changeDetector);

  //-----------------------------
  // ng2 life cycle
  //-----------------------------

  @override Stream<SerializableTuple1> provideState() => _modelTransformation$ctrl.stream
    .where((String value) => value != null && value.isNotEmpty)
    .distinct((String vA, String vB) => vA.compareTo(vB) == 0)
    .map((String value) => new SerializableTuple1()..item1 = value);

  @override void receiveState(Entity entity, StatePhase phase) {
    final SerializableTuple1 tuple = entity as SerializableTuple1;
    final String incoming = tuple.item1;

    _updateInnerHtmlTrusted(incoming, false);
  }

  @override void ngAfterViewInit() {
    _updateInnerHtmlTrusted(model, false);

    _initStreams();
  }

  @override void ngOnDestroy() {
    super.ngOnDestroy();

    contentElement.nativeElement.removeEventListener('DOMSubtreeModified', _contentModifier);

    _isDestroyCalled = true;

    _range$subscription?.cancel();
    _hasRangeSubscription?.cancel();
  }

  //-----------------------------
  // template methods
  //-----------------------------

  void transformSelection(HTMLTextTransformation transformationType) => _transformation$ctrl.add(transformationType);

  //-----------------------------
  // inner methods
  //-----------------------------

  void _updateInnerHtmlTrusted(String result, [bool notifyStateListeners=true]) {
    model = result;

    if (contentElement != null) contentElement.nativeElement.setInnerHtml(result, treeSanitizer: NodeTreeSanitizer.trusted);

    if (notifyStateListeners) _modelTransformation$ctrl.add(result);
  }

  void _initStreams() {
    _range$ = new rx.Observable.merge([
      document.onMouseUp,
      document.onKeyUp,
      rx.observable(_rangeTrigger$ctrl.stream),
    ], asBroadcastStream: true)
      .map((_) => window.getSelection())
      .map((Selection selection) {
        final List<Range> ranges = <Range>[];

        for (int i=0, len=selection.rangeCount; i<len; i++) {
          Range range = selection.getRangeAt(i);

          if (range.startContainer != range.endContainer || range.startOffset != range.endOffset) ranges.add(range);
        }

        return (ranges.isNotEmpty) ? ranges.first : null;
      }) as rx.Observable<Range>;

    _rangeTransform$ = _range$
      .tap((_) => _resetButtons())
      .where((Range range) => range != null)
      .tap(_analyzeRange)
      .flatMapLatest((Range range) => _transformation$ctrl.stream
        .take(1)
        .map((HTMLTextTransformation transformationType) => new Tuple2<Range, HTMLTextTransformation>(range, transformationType))
      ) as rx.Observable<Tuple2<Range, HTMLTextTransformation>>;

    contentElement.nativeElement.addEventListener('DOMSubtreeModified', _contentModifier);

    _range$subscription = _rangeTransform$
      .listen(_transformContent) as StreamSubscription<Tuple2<Range, HTMLTextTransformation>>;

    _hasRangeSubscription = _range$
      .map((Range range) {
        if (range == null) return false;

        Node currentNode = range.commonAncestorContainer;
        bool isOwnRange = false;

        while (currentNode != null) {
          if (currentNode == contentElement.nativeElement) {
            isOwnRange = true;

            break;
          }

          currentNode = currentNode.parentNode;
        }

        if (!isOwnRange) return false;

        return ((range.startContainer == range.endContainer) && (range.startOffset == range.endOffset)) ? false : true;
      })
      .listen(_hasSelectedRange$ctrl.add) as StreamSubscription<bool>;
  }

  void _contentModifier(Event event) {
    model = contentElement.nativeElement.innerHtml;

    _modelTransformation$ctrl.add(model);
  }

  void _transformContent(Tuple2<Range, HTMLTextTransformation> tuple) {
    final StringBuffer buffer = new StringBuffer();
    final Range range = tuple.item1;

    final DocumentFragment extractedContent = range.extractContents();

    if (tuple.item2.doRemoveTag) {
      transformer.removeTransformation(tuple.item2, extractedContent);

      if (tuple.item2.outerContainer != null) {
        buffer.write('<tmp_tag>');
        buffer.write(extractedContent.innerHtml);
        buffer.write('</tmp_tag>');
      } else {
        buffer.write(extractedContent.innerHtml);
      }

      tuple.item2.doRemoveTag = false;
    } else {
      buffer.write(_writeOpeningTag(tuple.item2));
      buffer.write(extractedContent.innerHtml);
      buffer.write(_writeClosingTag(tuple.item2));
    }

    range.insertNode(new DocumentFragment.html(buffer.toString(), treeSanitizer: NodeTreeSanitizer.trusted));

    if (tuple.item2.outerContainer != null) {
      range.selectNode(tuple.item2.outerContainer);

      final DocumentFragment extractedParentContent = range.extractContents();
      String result = extractedParentContent.innerHtml;

      result = result.replaceFirst(r'<tmp_tag>', _writeClosingTag(tuple.item2));
      result = result.replaceFirst(r'</tmp_tag>', _writeOpeningTag(tuple.item2));

      tuple.item2.outerContainer = null;

      range.insertNode(new DocumentFragment.html(result, treeSanitizer: NodeTreeSanitizer.trusted));
    }

    _rangeTrigger$ctrl.add(true);
  }

  String _writeOpeningTag(HTMLTextTransformation transformation) {
    final StringBuffer buffer = new StringBuffer();

    buffer.write('<${transformation.tag}');

    if (transformation.id != null) buffer.write(' id="${transformation.id}"');

    if (transformation.className != null) buffer.write(' class="${transformation.className}"');

    if (transformation.style != null) {
      final List<String> styleParts = <String>[];

      transformation.style.forEach((String K, String V) => styleParts.add('$K:$V'));

      buffer.write(' style="${styleParts.join(';')}"');
    }

    if (transformation.attributes != null) {
      final List<String> attributes = <String>[];

      transformation.attributes.forEach((String K, String V) {
        if (V == null || V.toLowerCase() == 'true') attributes.add(K);
        else attributes.add('$K="$V"');
      });

      buffer.write(' ${attributes.join(' ')}');
    }

    buffer.write('>');

    return buffer.toString();
  }

  String _writeClosingTag(HTMLTextTransformation transformation) => '</${transformation.tag}>';

  void _resetButtons() {
    List<HTMLTextTransformation> allButtons = buttons.fold(<HTMLTextTransformation>[], (List<HTMLTextTransformation> prev, List<HTMLTextTransformation> value) {
      prev.addAll(value);

      return prev;
    });

    allButtons.forEach((HTMLTextTransformation transformation) => transformation.doRemoveTag = false);

    changeDetector.markForCheck();
  }

  void _analyzeRange(Range range) {
    final DocumentFragment fragment = range.cloneContents();
    final List<String> encounteredElementFullNames = transformer.listChildTagsByFullName(fragment);

    List<HTMLTextTransformation> allButtons = buttons.fold(<HTMLTextTransformation>[], (List<HTMLTextTransformation> prev, List<HTMLTextTransformation> value) {
      prev.addAll(value);

      return prev;
    });

    allButtons.forEach((HTMLTextTransformation transformation) {
      final String tag = transformer.toNodeNameFromTransformation(transformation);

      transformation.doRemoveTag = encounteredElementFullNames.contains(tag);

      if (!transformation.doRemoveTag && range.startContainer == range.endContainer) {
        Node currentNode = range.startContainer;

        while (currentNode != null && currentNode != this.element.nativeElement) {
          if (transformer.toNodeNameFromElement(currentNode) == tag) {
            transformation.doRemoveTag = true;
            transformation.outerContainer = currentNode;

            break;
          }

          currentNode = currentNode.parentNode;
        }
      }
    });

    changeDetector.markForCheck();
  }
}