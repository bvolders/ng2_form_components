library ng2_form_components.infrastructure.list_renderer_service;

import 'dart:async';

import 'package:ng2_form_components/src/components/list_item.dart' show ListItem;

class ListRendererService {

  List<ListRendererEvent> lastResponders;

  Stream<ListItem> get rendererSelection$ => _rendererSelection$ctrl.stream;
  Stream<ItemRendererEvent> get event$ => _event$ctrl.stream;
  Stream<List<ListRendererEvent>> get responders$ => _responder$ctrl.stream;

  final StreamController<ListItem> _rendererSelection$ctrl = new StreamController<ListItem>.broadcast();
  final StreamController<ItemRendererEvent> _event$ctrl = new StreamController<ItemRendererEvent>.broadcast();
  final StreamController<List<ListRendererEvent>> _responder$ctrl = new StreamController<List<ListRendererEvent>>.broadcast();

  ListRendererService();

  void triggerSelection(ListItem listItem) => _rendererSelection$ctrl.add(listItem);

  void triggerEvent(ItemRendererEvent event) => _event$ctrl.add(event);

  void respondEvents(List<ListRendererEvent> events) {
    _responder$ctrl.add(events);

    lastResponders = events;
  }

}

class ListRendererEvent<T, U extends Comparable> {

  final String type;
  final ListItem<U> listItem;
  final T data;

  ListRendererEvent(this.type, this.listItem, this.data);

}

class ItemRendererEvent<T, U extends Comparable> {

  final String type;
  final ListItem<U> listItem;
  final T data;

  ItemRendererEvent(this.type, this.listItem, this.data);

}