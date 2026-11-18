import 'package:web/web.dart' as web;

import '../core/config.dart';

/// The worker app is a separate application (worker_app/), served by the same HeatGuard server at /worker/.
/// The dashboard only links to it; it never embeds the worker experience.
Uri workerAppUrl() {
  final api = Uri.parse(AppConfig.apiBaseUrl);
  return api.hasAuthority ? api.resolve('/worker/') : Uri.base.resolve('/worker/');
}

void openWorkerApp() => web.window.open(workerAppUrl().toString(), '_blank');
