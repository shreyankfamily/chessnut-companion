import 'package:url_launcher/url_launcher.dart';

import '../l10n/localized_material.dart';

Future<String?> showLichessTokenDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _LichessTokenDialog(),
    );

class _LichessTokenDialog extends StatefulWidget {
  const _LichessTokenDialog();

  @override
  State<_LichessTokenDialog> createState() => _LichessTokenDialogState();
}

class _LichessTokenDialogState extends State<_LichessTokenDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createToken() async {
    final uri = Uri.https('lichess.org', '/account/oauth/token/create', {
      'description': 'Companion Online',
      'scopes[]': [
        'board:play',
        'challenge:read',
        'challenge:write',
        'follow:read'
      ],
    });
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (mounted) {
      setState(() => _error =
          'Open lichess.org/account/oauth/token in your browser to create a token.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Connect your Lichess account'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create a personal token on Lichess with Play with the Board API, '
                'Read incoming challenges, Create/accept/decline challenges, and '
                'Read followed players permissions. Paste it below. '
                'Your token is stored securely on this device.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _createToken,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Create token on Lichess'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('lichess-personal-token'),
                controller: _controller,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration:
                    const InputDecoration(labelText: 'Personal access token'),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Connect Lichess'),
        ),
      ],
    );
  }
}
