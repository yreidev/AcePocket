import 'package:acepocket/features/container/models/container_inspect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Entrypoint 为 [""] 时启动命令不含前导空格', () {
    final inspect = ContainerInspect.fromJson({
      'Id': 'sha256:0123456789abcdef0123',
      'Name': '/web',
      'Config': {
        'Entrypoint': [''],
        'Cmd': ['nginx', '-g', 'daemon off;'],
      },
    });
    expect(inspect.commandLine, 'nginx -g daemon off;');
    expect(inspect.config.entrypoint, isEmpty);
    expect(inspect.config.cmd, ['nginx', '-g', 'daemon off;']);
  });
}
