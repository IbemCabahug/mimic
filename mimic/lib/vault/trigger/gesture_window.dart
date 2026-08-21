// lib/vault/trigger/gesture_window.dart

/// Extracts the trailing slice of recent taps matching the target gesture length.
///
/// A trigger detector calls this helper on each recorded tap to extract the
/// single candidate sequence worth verifying, avoiding up to five expensive
/// PBKDF2 derivations across varying window lengths.
///
/// Returns a new [List<int>] containing the last [length] entries of [tapHistory]
/// if [tapHistory] has at least [length] elements and [length] > 0.
/// Returns `null` if [length] <= 0 or if [tapHistory.length] < [length].
///
/// The input [tapHistory] is never mutated. The returned list is an independent copy.
List<int>? trailingWindow(List<int> tapHistory, int length) {
  if (length <= 0 || tapHistory.length < length) {
    return null;
  }
  return tapHistory.sublist(tapHistory.length - length);
}
