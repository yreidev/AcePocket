import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/section_card.dart';
import '../providers/cert_providers.dart';
import '../utils/pem_validation.dart';
import '../widgets/snack.dart';

/// 上传自有证书页 `/certs/upload`。
///
/// 对应 POST /api/cert/cert/upload（request.CertUpload）：
/// 面板会解析证书中的 DNSNames / IPAddresses 作为域名。
class CertUploadPage extends ConsumerStatefulWidget {
  const CertUploadPage({super.key});

  @override
  ConsumerState<CertUploadPage> createState() => _CertUploadPageState();
}

class _CertUploadPageState extends ConsumerState<CertUploadPage> {
  final TextEditingController _certController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _certController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cert = _certController.text.trim();
    final key = _keyController.text.trim();
    final certError = validatePemCertificate(cert);
    if (certError != null) {
      showSnack(context, certError, error: true);
      return;
    }
    final keyError = validatePemPrivateKey(key);
    if (keyError != null) {
      showSnack(context, keyError, error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref.read(certRepoProvider).uploadCert(cert: cert, key: key);
      if (!mounted) return;
      showSnack(context, '证书上传成功');
      context.pop(true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('上传证书')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SectionCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '粘贴 PEM 格式的证书（建议包含完整证书链）与对应私钥。'
                    '上传的证书不支持自动续签，域名由面板从证书中解析。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SectionCard(
            title: '证书（fullchain.pem）',
            child: TextField(
              controller: _certController,
              minLines: 8,
              maxLines: 14,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '-----BEGIN CERTIFICATE-----',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SectionCard(
            title: '私钥（private.key）',
            child: TextField(
              controller: _keyController,
              minLines: 6,
              maxLines: 12,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '-----BEGIN PRIVATE KEY-----',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_outlined),
              label: Text(_submitting ? '上传中…' : '上传证书'),
            ),
          ),
        ],
      ),
    );
  }
}
