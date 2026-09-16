"""在受限沙箱里驱动 Flutter / adb。

背景：agent 会话的 PATH 是启动时快照，运行期改 PATH 传不到子进程（表现为
"Failed to find git in search path"）。解决方式是在这里自行拼一套 env 再创建子进程。

用法:
  python run_flutter.py [--cwd <目录>] <flutter 子命令...>
  python run_flutter.py analyze
  python run_flutter.py pub get
"""

import os
import subprocess
import sys

DEV = r'D:\software\DEV'
FLUTTER_BAT = os.path.join(DEV, 'flutter', 'bin', 'flutter.bat')
JDK = os.path.join(DEV, 'jdk17')
SDK = os.path.join(DEV, 'android-sdk')
GIT_BIN = r'D:\Users\haku\.workbuddy\binaries\PortableGit\versions\1.2.0\bin'
DEFAULT_CWD = r'D:\Users\haku\WorkBuddy\2026-09-10-21-52-45\tracker'


def build_env():
    env = os.environ.copy()
    env['PATH'] = ';'.join([
        os.path.dirname(FLUTTER_BAT),
        os.path.join(JDK, 'bin'),
        os.path.join(SDK, 'platform-tools'),
        GIT_BIN,
        env.get('PATH', ''),
    ])
    env['JAVA_HOME'] = JDK
    env['ANDROID_HOME'] = SDK
    env['ANDROID_SDK_ROOT'] = SDK
    # 让 flutter.bat 自行推导 FLUTTER_ROOT，避免指向别的 SDK
    env.pop('FLUTTER_ROOT', None)
    return env


def main():
    args = sys.argv[1:]
    cwd = DEFAULT_CWD
    if args[:1] == ['--cwd']:
        cwd = args[1]
        args = args[2:]
    cmd = ['cmd', '/c', FLUTTER_BAT] + args
    print('$ ' + ' '.join(cmd), flush=True)
    proc = subprocess.run(
        cmd,
        cwd=cwd,
        env=build_env(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        errors='replace',
    )
    print(proc.stdout)
    print('exit:', proc.returncode)
    sys.exit(proc.returncode)


if __name__ == '__main__':
    main()
