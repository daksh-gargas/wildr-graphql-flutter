import 'package:graphql/client.dart';
import 'package:meta/meta.dart';

import 'package:gql_exec/gql_exec.dart';

import 'package:graphql/src/core/query_result.dart';
import 'package:graphql/src/core/policies.dart';
import 'package:graphql/src/exceptions.dart';
import 'package:normalize/normalize.dart';

/// Internal writeQuery wrapper
typedef _IntWriteQuery = void Function(
    Request request, Map<String, dynamic> data);

/// Internal [PartialDataException] handling callback
typedef _IntPartialDataHandler = MismatchedDataStructureException Function(
    PartialDataException failure);

extension InternalQueryWriteHandling on QueryManager {
  /// Merges exceptions into `queryResult` and
  /// returns `true` if a reread should be attempted
  ///
  /// This is named `*OrSetExceptionOnQueryResult` because it is very imperative,
  /// and edits the [queryResult] inplace.
  bool _writeQueryOrSetExceptionOnQueryResult(
    Request request,
    Map<String, dynamic> data,
    QueryResult queryResult, {
    @required _IntWriteQuery writeQuery,
    @required _IntPartialDataHandler onPartial,
  }) {
    try {
      writeQuery(request, data);
      return true;
    } on CacheMisconfigurationException catch (failure) {
      queryResult.exception = coalesceErrors(
        exception: queryResult.exception,
        linkException: failure,
      );
    } on PartialDataException catch (failure) {
      queryResult.exception = coalesceErrors(
        exception: queryResult.exception,
        linkException: onPartial(failure),
      );
    }
    return false;
  }

  /// Part of [InternalQueryWriteHandling], and not exposed outside the
  /// library.
  ///
  /// networked wrapper for [_writeQueryOrSetExceptionOnQueryResult]
  bool attemptCacheWriteFromResponse(
    FetchPolicy fetchPolicy,
    Request request,
    Response response,
    QueryResult queryResult,
  ) =>
      (fetchPolicy == FetchPolicy.noCache || response.data == null)
          ? false
          : _writeQueryOrSetExceptionOnQueryResult(
              request,
              response.data,
              queryResult,
              writeQuery: (req, data) => cache.writeQuery(req, data: data),
              onPartial: (failure) => UnexpectedResponseStructureException(
                failure,
                request: request,
                parsedResponse: response,
              ),
            );

  /// Part of [InternalQueryWriteHandling], and not exposed outside the
  /// library.
  ///
  /// client-side wrapper for [_writeQueryOrSetExceptionOnQueryResult]
  bool attemptCacheWriteFromClient(
    Request request,
    Map<String, dynamic> data,
    QueryResult queryResult, {
    @required _IntWriteQuery writeQuery,
  }) =>
      _writeQueryOrSetExceptionOnQueryResult(
        request,
        data,
        queryResult,
        writeQuery: writeQuery,
        onPartial: (failure) => MismatchedDataStructureException(
          failure,
          request: request,
          data: data,
        ),
      );
}
