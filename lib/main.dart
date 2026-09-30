import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://awikilzaoayfsumcwrja.supabase.co',
);
const supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_nEtcrvipB_yHX32oy884NQ_q1hg2vHN',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configured =
      supabaseUrl.startsWith('https://') && supabasePublishableKey.isNotEmpty;
  if (configured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }
  runApp(MozaqueApp(configured: configured));
}
