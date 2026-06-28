import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/app_exception.dart';

/// Low-level Firestore wrapper.
///
/// Translates [FirebaseException] codes into our [AppException] hierarchy.
/// All higher-level logic (retries, business rules) lives in repositories.
class FirestoreService {
  FirestoreService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> setDocument({
    required String collection,
    required String id,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _db.collection(collection).doc(id).set(data);
    } on FirebaseException catch (e) {
      throw _map(e);
    }
  }

  Future<void> updateDocument({
    required String collection,
    required String id,
    required Map<String, dynamic> data,
  }) async {
    try {
      await _db.collection(collection).doc(id).update(data);
    } on FirebaseException catch (e) {
      throw _map(e);
    }
  }

  Future<void> deleteDocument({
    required String collection,
    required String id,
  }) async {
    try {
      await _db.collection(collection).doc(id).delete();
    } on FirebaseException catch (e) {
      throw _map(e);
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> addDocument({
    required String collection,
    required Map<String, dynamic> data,
  }) async {
    try {
      return await _db.collection(collection).add(data);
    } on FirebaseException catch (e) {
      throw _map(e);
    }
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<DocumentSnapshot<Map<String, dynamic>>?> getDocument({
    required String collection,
    required String id,
  }) async {
    try {
      final doc = await _db.collection(collection).doc(id).get();
      return doc.exists ? doc : null;
    } on FirebaseException catch (e) {
      throw _map(e);
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> queryCollection({
    required String collection,
    List<QueryFilter> filters = const [],
    String? orderByField,
    bool descending = false,
    int? limit,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _db.collection(collection);

      for (final filter in filters) {
        query = query.where(
          filter.field,
          isEqualTo: filter.isEqualTo,
          isLessThan: filter.isLessThan,
          isGreaterThan: filter.isGreaterThan,
          arrayContains: filter.arrayContains,
        );
      }

      if (orderByField != null) {
        query = query.orderBy(orderByField, descending: descending);
      }
      if (limit != null) {
        query = query.limit(limit);
      }

      return query.get();
    } on FirebaseException catch (e) {
      throw _map(e);
    }
  }

  // ── Real-time ─────────────────────────────────────────────────────────────

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchDocument({
    required String collection,
    required String id,
  }) async* {
    // async* + await for is used instead of .handleError() because on Flutter
    // Web the JS interop error type fails a typed handleError callback.
    try {
      await for (final snap
          in _db.collection(collection).doc(id).snapshots()) {
        yield snap;
      }
    } on FirebaseException catch (e) {
      throw _map(e);
    } catch (e) {
      throw UnexpectedException.wrap(e);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchCollection({
    required String collection,
    List<QueryFilter> filters = const [],
    String? orderByField,
    bool descending = false,
    int? limit,
  }) async* {
    Query<Map<String, dynamic>> query = _db.collection(collection);

    for (final filter in filters) {
      query = query.where(
        filter.field,
        isEqualTo: filter.isEqualTo,
        arrayContains: filter.arrayContains,
      );
    }

    if (orderByField != null) {
      query = query.orderBy(orderByField, descending: descending);
    }
    if (limit != null) {
      query = query.limit(limit);
    }

    try {
      await for (final snap in query.snapshots()) {
        yield snap;
      }
    } on FirebaseException catch (e) {
      throw _map(e);
    } catch (e) {
      throw UnexpectedException.wrap(e);
    }
  }

  // ── Error mapping ─────────────────────────────────────────────────────────

  AppException _map(FirebaseException e) => switch (e.code) {
        'permission-denied' || 'unauthorized' =>
          DataException.permissionDenied(),
        'not-found' => DataException.notFound('Document'),
        'unavailable' ||
        'deadline-exceeded' ||
        'cancelled' =>
          DataException.unavailable(e),
        'already-exists' => DataException.alreadyExists('Document'),
        _ => DataException.unavailable(e),
      };
}

/// Typed query predicate passed to [FirestoreService.queryCollection].
class QueryFilter {
  const QueryFilter({
    required this.field,
    this.isEqualTo,
    this.isLessThan,
    this.isGreaterThan,
    this.arrayContains,
  });

  final String field;
  final Object? isEqualTo;
  final Object? isLessThan;
  final Object? isGreaterThan;
  final Object? arrayContains;
}
