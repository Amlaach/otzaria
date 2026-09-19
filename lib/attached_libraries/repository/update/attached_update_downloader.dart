import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:otzaria/attached_libraries/models/attached_update_manifest.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_artifact_builder.dart';
import 'package:otzaria/attached_libraries/repository/update/attached_update_fetcher.dart';
import 'package:otzaria/core/netfree_certificates.dart';

/// Progress of [AttachedUpdateDownloader.download]; `total == 0` while the
/// parts are assembled and hashed.
typedef AttachedUpdateProgress = void Function(int received, int total);

/// מוריד ומרכיב ארטיפקט עדכון ב-isolate נפרד.
///
/// Download, per-part sha256, zstd and the final sha256 of a multi-GB file
/// would each stall frames on the UI isolate, so the whole pipeline runs in
/// one worker isolate that trusts the NetFree CAs itself.
class AttachedUpdateDownloader {
  const AttachedUpdateDownloader({
    this.fetcher,
    this.builder = const AttachedUpdateArtifactBuilder(),
    this.certificates = loadNetfreeCaBytes,
    this.progressInterval = const Duration(milliseconds: 200),
  });

  /// Null means a default [AttachedUpdateFetcher].
  final AttachedUpdateFetcher? fetcher;
  final AttachedUpdateArtifactBuilder builder;
  final Future<List<Uint8List>> Function() certificates;
  final Duration progressInterval;

  /// Downloads [artifact] into [combinedPath] (resuming a partial file) and
  /// assembles the verified database at [outputPath].
  Future<void> download(
    AttachedUpdateArtifact artifact, {
    required String combinedPath,
    required String outputPath,
    AttachedUpdateProgress? onProgress,
    AttachedUpdateCancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw const AttachedUpdateCancelled();
    final certs = await certificates();
    final events = ReceivePort();
    SendPort? control;
    final unsubscribe = cancel?.onCancel(() => control?.send(null));
    events.listen((message) {
      if (message is SendPort) {
        control = message;
        if (cancel?.isCancelled ?? false) message.send(null);
      } else if (message is (int, int)) {
        onProgress?.call(message.$1, message.$2);
      }
    });
    final job = _Job(
      artifact: artifact,
      combinedPath: combinedPath,
      outputPath: outputPath,
      fetcher: fetcher ?? AttachedUpdateFetcher(),
      builder: builder,
      certificates: certs,
      events: events.sendPort,
      progressInterval: progressInterval,
    );
    try {
      await _spawn(job);
    } finally {
      unsubscribe?.call();
      events.close();
    }
  }

  // Static so the closure captures only [job], not the caller's context.
  static Future<void> _spawn(_Job job) => Isolate.run(() => _run(job));

  static Future<void> _run(_Job job) async {
    trustCertificates(job.certificates);
    final control = ReceivePort();
    final cancel = AttachedUpdateCancelToken();
    control.listen((_) => cancel.cancel());
    job.events.send(control.sendPort);
    try {
      var last = DateTime.fromMillisecondsSinceEpoch(0);
      await job.fetcher.downloadParts(
        job.artifact.parts,
        job.combinedPath,
        cancel: cancel,
        onProgress: (received, total) {
          final now = DateTime.now();
          if (received < total && now.difference(last) < job.progressInterval) {
            return;
          }
          last = now;
          job.events.send((received, total));
        },
      );
      if (cancel.isCancelled) throw const AttachedUpdateCancelled();
      job.events.send((0, 0));
      await job.builder.build(job.artifact, job.combinedPath, job.outputPath);
    } finally {
      control.close();
    }
  }
}

class _Job {
  const _Job({
    required this.artifact,
    required this.combinedPath,
    required this.outputPath,
    required this.fetcher,
    required this.builder,
    required this.certificates,
    required this.events,
    required this.progressInterval,
  });

  final AttachedUpdateArtifact artifact;
  final String combinedPath;
  final String outputPath;
  final AttachedUpdateFetcher fetcher;
  final AttachedUpdateArtifactBuilder builder;
  final List<Uint8List> certificates;
  final SendPort events;
  final Duration progressInterval;
}
