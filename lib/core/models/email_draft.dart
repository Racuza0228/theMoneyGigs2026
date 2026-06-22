// models/email_draft.dart
// Output object from EmailTemplateBuilder — passed directly to url_launcher.

class EmailDraft {
  final String toAddress;
  final String subject;
  final String body;

  const EmailDraft({
    required this.toAddress,
    required this.subject,
    required this.body,
  });

  /// Builds a mailto: URI string ready for url_launcher.
  String toMailtoUri() {
    final encodedSubject = Uri.encodeComponent(subject);
    final encodedBody = Uri.encodeComponent(body);
    return 'mailto:$toAddress?subject=$encodedSubject&body=$encodedBody';
  }
}