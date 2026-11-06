import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/cho_store.dart';

/// First run: the server confirms this CHO and says which compound they belong to.
/// There is no compound picker, so a phone can't be set up against the wrong one.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.onComplete,
    this.api,
    this.store,
  });

  final ValueChanged<ChoIdentity> onComplete;
  final ApiClient? api;
  final ChoStore? store;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _phone = TextEditingController();
  late final ApiClient _api = widget.api ?? ApiClient();
  late final ChoStore _store = widget.store ?? ChoStore();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter your phone number');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    String? error;
    ChoIdentity? identity;
    try {
      identity = ChoIdentity.fromJson(await _api.lookupCho(phone));
      await _store.save(identity);
    } on ApiException catch (e) {
      error = e.statusCode >= 500
          ? 'The server is having a problem. Try again shortly.'
          : e.reason;
    } catch (_) {
      error = 'No connection. Setup needs internet once. '
          'If this is an emergency, call the driver and hospital directly.';
    }
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = error;
    });
    if (identity != null) widget.onComplete(identity);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up this phone')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Enter the phone number you were registered with as a CHO.',
            style: TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('setup_phone'),
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Your phone number'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('setup_error'),
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Checking…' : 'Continue'),
          ),
        ],
      ),
    );
  }
}
