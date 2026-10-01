import 'package:flutter_test/flutter_test.dart';
import 'package:mozaque/data/mozaque_repository.dart';

void main() {
  test(
    'invite links open the live web app and preserve the invitation code',
    () {
      final link = Uri.parse(mozaqueInviteLink('test-code+with/slash'));

      expect(link.scheme, 'https');
      expect(link.host, 'mozaque.com');
      expect(link.path, '/');
      expect(link.queryParameters['invite'], 'test-code+with/slash');
    },
  );
}
