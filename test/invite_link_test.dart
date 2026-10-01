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

  test('profile links open a sign-up-ready page on the live domain', () {
    final link = Uri.parse(mozaqueProfileLink('joel_dickinson'));

    expect(link.scheme, 'https');
    expect(link.host, 'mozaque.com');
    expect(link.path, '/joel_dickinson');
    expect(mozaqueProfileSlugFromUri(link), 'joel_dickinson');
  });

  test('old query-based profile links remain supported', () {
    final oldLink = Uri.parse('https://mozaque.com/?person=joel_dickinson');

    expect(mozaqueProfileSlugFromUri(oldLink), 'joel_dickinson');
  });

  test('profile sign-up confirmation resumes the connection request', () {
    final redirect = Uri.parse(mozaqueProfileSignupRedirect('joel_dickinson'));

    expect(redirect.path, '/');
    expect(redirect.queryParameters['person'], 'joel_dickinson');
    expect(redirect.queryParameters['connect'], '1');
    expect(mozaqueProfileSlugFromUri(redirect), 'joel_dickinson');
  });

  test('non-profile app paths are not treated as profile links', () {
    expect(
      mozaqueProfileSlugFromUri(Uri.parse('https://mozaque.com/people')),
      isNull,
    );
    expect(
      mozaqueProfileSlugFromUri(Uri.parse('https://mozaque.com/a/b')),
      isNull,
    );
  });
}
