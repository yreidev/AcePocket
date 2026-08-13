import 'package:flutter/material.dart';

import '../../../core/widgets/a11y.dart';

// 提示统一走 core 的 `widgets/app_snack.dart`
// （`showSuccessSnack` / `showErrorSnack` / `showInfoSnack`），
// 错误文案由 core 的 `describeError` 提取，本模块不再自建 SnackBar 与文案函数：
// 旧实现只改了 backgroundColor 而没改前景色，浅色主题下近白字浮在浅粉底上不可读。

// ------------------------------------------------------------------ 表单校验

/// 用户名校验：与面板一致（`internal/request/user.go` 的
/// `regex:"^[a-zA-Z0-9_-]+$"`），仅允许字母、数字、下划线与连字符。
String? validateUsername(String value) {
  if (value.isEmpty) return '请输入用户名';
  if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(value)) {
    return '只能包含字母、数字、下划线与连字符';
  }
  return null;
}

/// 邮箱校验（面板要求 `email` 格式）。
String? validateEmail(String value) {
  if (value.isEmpty) return '请输入邮箱';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
    return '邮箱格式不正确';
  }
  return null;
}

/// 密码校验（面板要求一定强度，这里先做基础长度检查，最终以面板返回为准）。
String? validatePassword(String value) {
  if (value.isEmpty) return '请输入密码';
  if (value.length < 8) return '密码至少 8 位';
  return null;
}

// ------------------------------------------------------------------ 通用对话框

/// 单行文本输入对话框，返回用户输入（取消返回 null）。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? label,
  String? helperText,
  TextInputType keyboardType = TextInputType.text,
  String confirmText = '保存',
  String? Function(String value)? validator,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      initialValue: initialValue,
      label: label,
      helperText: helperText,
      keyboardType: keyboardType,
      confirmText: confirmText,
      validator: validator,
    ),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.initialValue,
    required this.label,
    required this.helperText,
    required this.keyboardType,
    required this.confirmText,
    required this.validator,
  });

  final String title;
  final String initialValue;
  final String? label;
  final String? helperText;
  final TextInputType keyboardType;
  final String confirmText;
  final String? Function(String value)? validator;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    final error = widget.validator?.call(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          helperMaxLines: 3,
          errorText: _error,
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

/// 密码设置对话框（需两次输入一致），返回密码（取消返回 null）。
Future<String?> showPasswordDialog(
  BuildContext context, {
  required String title,
  String? helperText,
  String confirmText = '保存',
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PasswordDialog(
      title: title,
      helperText: helperText,
      confirmText: confirmText,
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({
    required this.title,
    required this.helperText,
    required this.confirmText,
  });

  final String title;
  final String? helperText;
  final String confirmText;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;

  /// 密码本身不合规（长度不足等），展示在「新密码」输入框下。
  String? _passwordError;

  /// 两次输入不一致，展示在「确认密码」输入框下。
  String? _confirmError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _clearErrors() {
    if (_passwordError == null && _confirmError == null) return;
    setState(() {
      _passwordError = null;
      _confirmError = null;
    });
  }

  void _submit() {
    final password = _password.text;
    // 错误要落在出问题的那个输入框上：旧实现把「密码至少 8 位」显示在
    // 「确认密码」下方，用户会以为是确认框填错了。
    final passwordError = validatePassword(password);
    final confirmError = passwordError == null && password != _confirm.text
        ? '两次输入的密码不一致'
        : null;
    if (passwordError != null || confirmError != null) {
      setState(() {
        _passwordError = passwordError;
        _confirmError = confirmError;
      });
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      // 小屏 + 弹出键盘 + 多行错误提示时内容会超出可用高度，必须可滚动。
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _password,
              autofocus: true,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '新密码',
                helperText: widget.helperText,
                helperMaxLines: 3,
                errorText: _passwordError,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
                suffixIcon: A11yIconButton(
                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) => _clearErrors(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '确认密码',
                errorText: _confirmError,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearErrors(),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.confirmText)),
      ],
    );
  }
}

/// 新建用户表单的结果。
class NewUserForm {
  const NewUserForm({
    required this.username,
    required this.password,
    required this.email,
  });

  final String username;
  final String password;
  final String email;
}

/// 新建面板用户对话框（`POST /api/users`），取消返回 null。
Future<NewUserForm?> showCreateUserDialog(BuildContext context) {
  return showDialog<NewUserForm>(
    context: context,
    builder: (context) => const _CreateUserDialog(),
  );
}

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  String? _usernameError;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final username = _username.text.trim();
    final email = _email.text.trim();
    final password = _password.text;
    final usernameError = validateUsername(username);
    final emailError = validateEmail(email);
    final passwordError = validatePassword(password);
    if (usernameError != null || emailError != null || passwordError != null) {
      setState(() {
        _usernameError = usernameError;
        _emailError = emailError;
        _passwordError = passwordError;
      });
      return;
    }
    Navigator.of(context).pop(
      NewUserForm(username: username, password: password, email: email),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建面板用户'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _username,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '用户名',
                helperText: '字母、数字、下划线与连字符',
                errorText: _usernameError,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_usernameError != null) {
                  setState(() => _usernameError = null);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: '邮箱',
                errorText: _emailError,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) {
                if (_emailError != null) setState(() => _emailError = null);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: '密码',
                helperText: '至少 8 位，建议包含大小写字母与数字',
                helperMaxLines: 2,
                errorText: _passwordError,
                errorMaxLines: 2,
                border: const OutlineInputBorder(),
                suffixIcon: A11yIconButton(
                  tooltip: _obscure ? '显示密码' : '隐藏密码',
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: (_) {
                if (_passwordError != null) {
                  setState(() => _passwordError = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('创建')),
      ],
    );
  }
}
