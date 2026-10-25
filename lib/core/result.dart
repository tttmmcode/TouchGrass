import 'errors/app_exception.dart';

/// A discriminated union of success ([Ok]) and failure ([Err]).
///
/// All repository methods return [Result<T>] so the UI layer
/// never has to reason about raw exceptions.
///
/// ```dart
/// final result = await challengeRepo.fetchToday();
/// result.when(
///   ok: (challenge) => state = AsyncData(challenge),
///   err: (e) => state = AsyncError(e, StackTrace.current),
/// );
/// ```
sealed class Result<T> {
  const Result();

  factory Result.ok(T value) = Ok<T>;
  factory Result.err(AppException exception) = Err<T>;

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Returns the value or throws the contained [AppException].
  T get valueOrThrow => switch (this) {
    Ok(:final value) => value,
    Err(:final exception) => throw exception,
  };

  /// Returns the exception or throws [StateError] if this is [Ok].
  AppException get exceptionOrThrow => switch (this) {
    Ok() => throw StateError('Result is Ok, not Err'),
    Err(:final exception) => exception,
  };

  /// Returns the value or null.
  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  /// Transform the success value; error passes through unchanged.
  Result<U> map<U>(U Function(T value) transform) => switch (this) {
    Ok(:final value) => Result.ok(transform(value)),
    Err(:final exception) => Result.err(exception),
  };

  /// Chain async operations that each produce a [Result].
  Result<U> flatMap<U>(Result<U> Function(T value) transform) => switch (this) {
    Ok(:final value) => transform(value),
    Err(:final exception) => Result.err(exception),
  };

  /// Exhaustive pattern match — both branches must return [R].
  R when<R>({
    required R Function(T value) ok,
    required R Function(AppException exception) err,
  }) => switch (this) {
    Ok(:final value) => ok(value),
    Err(:final exception) => err(exception),
  };

  /// Side-effect on success; returns `this` for chaining.
  Result<T> onOk(void Function(T value) action) {
    if (this case Ok(:final value)) action(value);
    return this;
  }

  /// Side-effect on failure; returns `this` for chaining.
  Result<T> onErr(void Function(AppException exception) action) {
    if (this case Err(:final exception)) action(exception);
    return this;
  }
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.exception);
  final AppException exception;
}

// ── Guard helpers ─────────────────────────────────────────────────────────

/// Wraps a potentially-throwing async call into a [Result].
///
/// [AppException] subtypes pass through; everything else is wrapped in
/// [UnexpectedException] for Crashlytics reporting.
Future<Result<T>> guardAsync<T>(Future<T> Function() action) async {
  try {
    return Result.ok(await action());
  } on AppException catch (e) {
    return Result.err(e);
  } catch (e) {
    return Result.err(UnexpectedException.wrap(e));
  }
}

/// Sync variant of [guardAsync].
Result<T> guard<T>(T Function() action) {
  try {
    return Result.ok(action());
  } on AppException catch (e) {
    return Result.err(e);
  } catch (e) {
    return Result.err(UnexpectedException.wrap(e));
  }
}
