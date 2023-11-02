import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;

class ShelfResponse {
  static shelf.Response blank(Map<String, String> headers) {
    return shelf.Response.ok(null, headers: headers);
  }

  static shelf.Response ok(Object? object, {Object? Function(Object? nonEncodable)? toEncodable}) {
    return shelf.Response.ok(
      object != null ? jsonEncode(object, toEncodable: toEncodable) : object,
      headers: {'content-type': 'application/json'},
    );
  }

  static shelf.Response created(Object? object, {Object? Function(Object? nonEncodable)? toEncodable}) {
    return shelf.Response(HttpStatus.created,
      body: object != null ? jsonEncode(object, toEncodable: toEncodable) : object,
      headers: {'content-type': 'application/json'},
    );
  }

  static shelf.Response forbidden(Object? object, {Object? Function(Object? nonEncodable)? toEncodable}) {
    return shelf.Response.forbidden(
      object != null ? jsonEncode(object, toEncodable: toEncodable) : object,
      headers: {'content-type': 'application/json'},
    );
  }

  static shelf.Response notFound(Object? object, {Object? Function(Object? nonEncodable)? toEncodable}) {
    return shelf.Response.notFound(
      object != null ? jsonEncode(object, toEncodable: toEncodable) : object,
      headers: {'content-type': 'application/json'},
    );
  }

  static shelf.Response internalServerError(Object? object, {Object? Function(Object? nonEncodable)? toEncodable}) {
    return shelf.Response.internalServerError(
      body: object != null ? jsonEncode(object, toEncodable: toEncodable) : object,
      headers: {'content-type': 'application/json'},
    );
  }
}
