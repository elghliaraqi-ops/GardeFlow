class QcmGenerationRetryPolicy {
  const QcmGenerationRetryPolicy._();

  static const int maxAutomaticFailures = 4;
  static const Duration resetWindow = Duration(hours: 24);

  static const List<Duration> _delays = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  static Duration delayForFailure(int failureCount) {
    if (failureCount <= 1) return _delays.first;
    final index = failureCount - 1;
    if (index >= _delays.length) return _delays.last;
    return _delays[index];
  }

  static bool isPermanentHttpStatus(int? status) {
    return status == 400 || status == 401 || status == 403 || status == 404;
  }

  static bool isRetryableHttpStatus(int? status) {
    if (status == null) return true;
    if (isPermanentHttpStatus(status)) return false;
    return status == 202 || status == 408 || status == 429 || status >= 500;
  }
}
