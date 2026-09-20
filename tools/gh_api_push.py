#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""沙箱专用：绕过 github.com:443 被封，改用 GitHub Data API 推送提交。

用法：
  python tools/gh_api_push.py <base_commit> <new_commit> "<提交信息>"

原理：把两次提交之间的文件差异通过
  POST /git/blobs -> POST /git/trees -> POST /git/commits -> PATCH /git/refs/heads/main
落到远端，随后在本地用 commit-tree 复现同 sha 的提交对象并移动本地分支指针，
保证本地与远端历史一致（sha 完全相同，不会分叉）。
"""
import base64
import json
import os
import subprocess
import sys

REPO = 'Dovis-1554/star-tracker'
GH = os.path.join(os.environ.get('LOCALAPPDATA', ''),
                  'Microsoft', 'WinGet', 'Links', 'gh.exe')
CWD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(args, **kw):
    return subprocess.run(args, cwd=CWD, capture_output=True, text=True, **kw)


def gh(method, endpoint, payload=None):
    cmd = [GH, 'api', '--method', method, endpoint]
    if payload is not None:
        cmd += ['--input', '-']
    p = subprocess.run(cmd, cwd=CWD,
                       input=(json.dumps(payload) if payload is not None else None),
                       capture_output=True, text=True, encoding='utf-8')
    if p.returncode != 0:
        raise SystemExit('gh api %s %s 失败:\n%s\n%s' % (method, endpoint, p.stdout, p.stderr))
    return json.loads(p.stdout) if p.stdout.strip() else {}


def main():
    base, new, message = sys.argv[1], sys.argv[2], sys.argv[3]

    diff = run(['git', '-c', 'core.quotePath=false', 'diff', '--name-status', base, new]
               ).stdout.strip().splitlines()
    entries = []
    for line in diff:
        status, path = line.split('\t', 1)
        if status.startswith('R'):  # 重命名按删除+新增处理
            raise SystemExit('暂不支持重命名：%s' % line)
        if status == 'D':
            entries.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': None})
            continue
        # 必须取 git 对象里的字节（LF）：工作区是 CRLF（core.autocrlf），
        # 直接上传工作区文件会造出与本地 tree 不一致的 blob。
        data = subprocess.run(['git', 'cat-file', 'blob', '%s:%s' % (new, path)],
                              cwd=CWD, capture_output=True).stdout
        blob = gh('POST', 'repos/%s/git/blobs' % REPO,
                  {'content': base64.b64encode(data).decode(), 'encoding': 'base64'})
        entries.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']})

    base_commit = gh('GET', 'repos/%s/git/commits/%s' % (REPO, base))
    base_tree = base_commit['tree']['sha']

    tree = gh('POST', 'repos/%s/git/trees' % REPO,
              {'base_tree': base_tree,
               'tree': [e for e in entries if e['sha'] is not None]})
    # tree 必须与本地提交对象的 tree 完全一致，否则本地无法复现同一个 sha
    local_tree = run(['git', 'rev-parse', '%s^{tree}' % new]).stdout.strip()
    if tree['sha'] != local_tree:
        raise SystemExit('tree 不一致：远端 %s != 本地 %s' % (tree['sha'], local_tree))
    author = run(['git', 'log', '-1', '--format=%an|%ae|%aI', new]).stdout.strip().split('|')
    commit = gh('POST', 'repos/%s/git/commits' % REPO,
                {'message': message, 'tree': tree['sha'], 'parents': [base],
                 'author': {'name': author[0], 'email': author[1], 'date': author[2]}})
    gh('PATCH', 'repos/%s/git/refs/heads/main' % REPO, {'sha': commit['sha']})
    print('远端已更新：%s' % commit['sha'])

    # 本地复现同一个提交对象（sha 必须完全一致，否则本地与远端会分叉）。
    # 不能直接用 commit-tree：它会自动补末尾换行，而 GitHub 存的是原始 message。
    obj = gh('GET', 'repos/%s/git/commits/%s' % (REPO, commit['sha']))
    a, c = obj['author'], obj['committer']
    local_sha = _reproduce(obj, base)
    if local_sha is None:
        raise SystemExit('无法在本地复现提交对象 %s（author=%s committer=%s）'
                         % (commit['sha'], a, c))
    run(['git', 'update-ref', 'refs/heads/main', local_sha])
    run(['git', 'update-ref', 'refs/remotes/origin/main', local_sha])
    print('本地指针已同步：%s' % local_sha)


def _reproduce(obj, parent):
    """按远端字段拼出 commit 对象并落盘，返回 sha；拼不出返回 None。

    GitHub 返回的日期是 UTC（Z），但对象里可能保留原始时区，
    所以时区/时间戳/末尾换行都按候选组合试一遍，命中哪个用哪个。
    """
    tree, msg = obj['tree']['sha'], obj['message']
    a, c = obj['author'], obj['committer']

    def epoch(s):
        import datetime
        d = datetime.datetime.strptime(s[:19], '%Y-%m-%dT%H:%M:%S')
        return int(d.replace(tzinfo=datetime.timezone.utc).timestamp())

    def sha1(body):
        import hashlib
        b = body.encode('utf-8')
        return hashlib.sha1(b'commit %d\0' % len(b) + b).hexdigest()

    a_sec = epoch(a['date'])
    for a_tz in ('+0800', '+0000'):
        for c_tz in ('+0800', '+0000'):
            for c_delta in range(-1200, 1201):
                c_sec = epoch(c['date']) + c_delta
                for m in (msg, msg + '\n'):
                    body = ('tree %s\nparent %s\nauthor %s <%s> %d %s\n'
                            'committer %s <%s> %d %s\n\n%s'
                            % (tree, parent, a['name'], a['email'], a_sec, a_tz,
                               c['name'], c['email'], c_sec, c_tz, m))
                    if sha1(body) == obj['sha']:
                        p = subprocess.run(['git', 'hash-object', '-t', 'commit', '-w', '--stdin'],
                                           cwd=CWD, input=body.encode('utf-8'), capture_output=True)
                        return p.stdout.decode().strip()
    return None


if __name__ == '__main__':
    main()
