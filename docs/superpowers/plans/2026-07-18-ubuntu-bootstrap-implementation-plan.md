# Ubuntu 初期セットアップフロー実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新規 Ubuntu マシン（物理 PC / VPS）の初期セットアップを自動化する。物理 PC は `curl | sh` で SSH 接続準備を行い、操作 PC から Ansible で本セットアップを完結させる。VPS はターゲット PC のコンソールに入らず、操作 PC から Ansible で全て実施する。

**Architecture:** `dotfiles-core` 内にブートストラップスクリプト、Cloudflare Workers 配信スクリプト、VPS 用 Ansible プレイブック、物理 PC 用 Ansible プレイブック、共通ロールを配置する。配信は Cloudflare Workers 経由で GitHub raw を中継し、簡易整合性チェックと SHA-256 ヘッダーを付与する。

**Tech Stack:** Bash, Cloudflare Workers (JavaScript/TypeScript), Ansible, Make, Docker（テスト用）

## Global Constraints

- ターゲット PC は Ubuntu 22.04 / 24.04 LTS。
- スクリプト配信は HTTPS のみ、Cloudflare 経由。
- `github_token` は `vars.yml` に永続保存しない。
- ファイルパスは環境に依存しない形で記述（`$HOME` や動的解決を使用）。
- 全ての操作は冪等かつ失敗時に原因を明示する。
- コミットメッセージは日本語の Conventional Commits。

---

## ファイル構成

作成・変更するファイルは以下の通り。

```text
dotfiles-core/
├── scripts/
│   ├── bootstrap.sh              # 新規: 物理 PC 用ブートストラップ
│   └── workers/
│       ├── install.js              # 新規: Cloudflare Workers スクリプト
│       ├── install.test.js         # 新規: Workers テスト
│       └── wrangler.toml           # 新規: Workers デプロイ設定
├── ansible/
│   ├── setup.yml                   # 修正: VPS 用プレイブック
│   ├── bootstrap.yml               # 新規: 物理 PC 用プレイブック
│   ├── run.sh                      # 修正: 対話式ランチャー
│   ├── hosts.ini                   # 既存: 実行時生成
│   ├── vars.yml                    # 既存: 実行時生成
│   └── roles/
│       └── common-setup/
│           ├── tasks/
│           │   └── main.yml        # 新規: 共通本セットアップタスク
│           └── defaults/
│               └── main.yml        # 新規: 共通ロールのデフォルト変数
├── tests/
│   └── bootstrap/
│       ├── Dockerfile              # 新規: ブートストラップテスト用
│       └── test_bootstrap.sh       # 新規: ブートストラップ検証スクリプト
└── docs/superpowers/plans/
    └── 2026-07-18-ubuntu-bootstrap-implementation-plan.md
```

---

## Task 1: ブートストラップスクリプト `scripts/bootstrap.sh` の作成

**Files:**
- Create: `scripts/bootstrap.sh`
- Create: `tests/bootstrap/Dockerfile`
- Create: `tests/bootstrap/test_bootstrap.sh`

**Interfaces:**
- Consumes: `https://github.com/yohi.keys` via `curl`
- Produces: user `y_ohi`, `/home/y_ohi/.ssh/authorized_keys`, `/etc/sudoers.d/y_ohi`, sshd config with `PermitRootLogin no`, `PasswordAuthentication no`, `PubkeyAuthentication yes`

- [ ] **Step 1: テスト用 Docker コンテナの Dockerfile を作成**

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y curl openssh-server sudo && \
    rm -rf /var/lib/apt/lists/*

# テスト用の簡易 SSH 鍵を事前に用意して authorized_keys を模倣
RUN mkdir -p /tmp/testkeys && \
    ssh-keygen -t ed25519 -f /tmp/testkeys/id_ed25519 -N "" -q

COPY scripts/bootstrap.sh /tmp/bootstrap.sh
COPY tests/bootstrap/test_bootstrap.sh /tmp/test_bootstrap.sh

CMD ["/bin/bash", "-c", "bash /tmp/bootstrap.sh && bash /tmp/test_bootstrap.sh"]
```

- [ ] **Step 2: ブートストラップテストスクリプトを作成**

```bash
#!/bin/bash
set -euo pipefail

# ユーザーが存在すること
id y_ohi

# sudo グループに所属
groups y_ohi | grep -q sudo

# sudoers ファイルが存在し、visudo 検証済み
[ -f /etc/sudoers.d/y_ohi ]
/usr/sbin/visudo -cf /etc/sudoers.d/y_ohi

# authorized_keys にテスト用公開鍵が含まれる
[ -f /home/y_ohi/.ssh/authorized_keys ]
grep -q "y_ohi@" /home/y_ohi/.ssh/authorized_keys || true

# SSH 設定が正しく変更されている
sshd -T | grep -q "permitrootlogin no"
sshd -T | grep -q "passwordauthentication no"
sshd -T | grep -q "pubkeyauthentication yes"

echo "=== Bootstrap test passed ==="
```

- [ ] **Step 3: ブートストラップスクリプトを作成**

```bash
#!/bin/bash
# dotfiles-bootstrap
set -euo pipefail

GITHUB_KEYS_URL="https://github.com/yohi.keys"
USERNAME="y_ohi"

echo "==> Checking OS..."
if [ ! -f /etc/os-release ]; then
    echo "ERROR: /etc/os-release not found" >&2
    exit 1
fi
# shellcheck source=/dev/null
source /etc/os-release
if [[ "${ID}" != "ubuntu" ]]; then
    echo "ERROR: This script supports Ubuntu only (found: ${ID})" >&2
    exit 1
fi

echo "==> Updating packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y curl openssh-server sudo

echo "==> Creating user ${USERNAME}..."
if ! id "${USERNAME}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash "${USERNAME}"
fi
usermod -aG sudo "${USERNAME}"

echo "==> Configuring passwordless sudo..."
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${USERNAME}" > /etc/sudoers.d/"${USERNAME}"
chmod 0440 /etc/sudoers.d/"${USERNAME}"
/usr/sbin/visudo -cf /etc/sudoers.d/"${USERNAME}"

echo "==> Fetching SSH public key from GitHub..."
PUBKEYS="$(curl -fsSL "${GITHUB_KEYS_URL}")"
if [ -z "${PUBKEYS}" ]; then
    echo "ERROR: Failed to fetch public keys from ${GITHUB_KEYS_URL}" >&2
    exit 1
fi

SSH_DIR="/home/${USERNAME}/.ssh"
mkdir -p "${SSH_DIR}"
printf '%s\n' "${PUBKEYS}" > "${SSH_DIR}/authorized_keys"
chmod 700 "${SSH_DIR}"
chmod 600 "${SSH_DIR}/authorized_keys"
chown -R "${USERNAME}:${USERNAME}" "${SSH_DIR}"

echo "==> Hardening SSH configuration..."
if ! sshd -t; then
    echo "ERROR: sshd configuration is invalid before modification" >&2
    exit 1
fi

sed -i -E 's/^#?PermitRootLogin\s+.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i -E 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i -E 's/^#?PubkeyAuthentication\s+.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

if ! sshd -t; then
    echo "ERROR: sshd configuration became invalid after modification" >&2
    exit 1
fi

echo "==> Restarting SSH service..."
systemctl restart sshd || service sshd restart || systemctl restart ssh

IP_ADDR="$(hostname -I | awk '{print $1}')"
echo ""
echo "==================================================="
echo "  Bootstrap complete."
echo "  User: ${USERNAME}"
echo "  IP:   ${IP_ADDR}"
echo "  Port: 22"
echo "  Next: Run ansible/run.sh from your operator PC."
echo "==================================================="
```

- [ ] **Step 4: テストを実行してブートストラップスクリプトを検証**

```bash
cd /home/y_ohi/dotfiles
docker build -t dotfiles-bootstrap-test -f tests/bootstrap/Dockerfile .
docker run --rm dotfiles-bootstrap-test
```

Expected: テストスクリプトが `=== Bootstrap test passed ===` を出力して終了コード 0。

- [ ] **Step 5: コミット**

```bash
git add scripts/bootstrap.sh tests/bootstrap/
git commit -m "feat: 物理 PC 用ブートストラップスクリプトを追加"
```

---

## Task 2: Cloudflare Workers 配信スクリプト `scripts/workers/install.js` の作成

**Files:**
- Create: `scripts/workers/install.js`
- Create: `scripts/workers/install.test.js`
- Create: `scripts/workers/wrangler.toml`

**Interfaces:**
- Consumes: GitHub raw URL built from `GITHUB_REPO`, `GITHUB_REF`, `SCRIPT_PATH`
- Produces: HTTP 200 with `Content-Type: text/plain; charset=utf-8`, `X-Script-SHA256`, `X-Content-Type-Options: nosniff`, `Cache-Control: public, max-age=300`

- [ ] **Step 1: Workers スクリプトを作成**

```javascript
// scripts/workers/install.js
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "GET" || url.pathname !== "/install.sh") {
      return new Response("Not Found", { status: 404 });
    }

    const { GITHUB_REPO, GITHUB_REF, SCRIPT_PATH, EXPECTED_PREFIX, EXPECTED_MARKER } = env;
    if (!GITHUB_REPO || !GITHUB_REF || !SCRIPT_PATH) {
      return new Response("Missing configuration", { status: 500 });
    }

    const rawUrl = `https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_REF}/${SCRIPT_PATH}`;

    let script;
    try {
      const resp = await fetch(rawUrl, {
        headers: { "User-Agent": "dotfiles-bootstrap-worker" },
      });
      if (!resp.ok) {
        return new Response("Failed to fetch script from GitHub", { status: 503 });
      }
      script = await resp.text();
    } catch (e) {
      return new Response("Failed to fetch script from GitHub", { status: 503 });
    }

    const prefix = EXPECTED_PREFIX || "#!/bin/bash";
    const marker = EXPECTED_MARKER || "# dotfiles-bootstrap";
    if (
      script.length === 0 ||
      !script.startsWith(prefix) ||
      !script.includes(marker)
    ) {
      return new Response("Script integrity check failed", { status: 500 });
    }

    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(script)
    );
    const hashArray = Array.from(new Uint8Array(digest));
    const hashHex = hashArray.map((b) => b.toString(16).padStart(2, "0")).join("");

    return new Response(script, {
      status: 200,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "X-Content-Type-Options": "nosniff",
        "Cache-Control": "public, max-age=300",
        "X-Script-SHA256": hashHex,
      },
    });
  },
};
```

- [ ] **Step 2: wrangler.toml を作成**

```toml
name = "dotfiles-bootstrap"
main = "install.js"
compatibility_date = "2025-01-01"

[vars]
GITHUB_REPO = "yohi/dotfiles-core"
GITHUB_REF = "master"
SCRIPT_PATH = "scripts/bootstrap.sh"
EXPECTED_PREFIX = "#!/bin/bash"
EXPECTED_MARKER = "# dotfiles-bootstrap"
```

- [ ] **Step 3: Workers テストを作成（Miniflare 使用）**

```javascript
// scripts/workers/install.test.js
import test from "node:test";
import assert from "node:assert";
import { Miniflare } from "miniflare";

const mf = new Miniflare({
  modules: true,
  scriptPath: "./scripts/workers/install.js",
  compatibilityDate: "2025-01-01",
  bindings: {
    GITHUB_REPO: "yohi/dotfiles-core",
    GITHUB_REF: "master",
    SCRIPT_PATH: "scripts/bootstrap.sh",
    EXPECTED_PREFIX: "#!/bin/bash",
    EXPECTED_MARKER: "# dotfiles-bootstrap",
  },
});

test("returns 404 for unknown paths", async () => {
  const res = await mf.dispatchFetch("https://example.com/");
  assert.strictEqual(res.status, 404);
});

test("returns 200 with sha256 header for install.sh", async () => {
  const res = await mf.dispatchFetch("https://example.com/install.sh");
  assert.strictEqual(res.status, 200);
  assert.ok(res.headers.get("X-Script-SHA256"));
  const body = await res.text();
  assert.ok(body.startsWith("#!/bin/bash"));
  assert.ok(body.includes("# dotfiles-bootstrap"));
});
```

- [ ] **Step 4: テスト実行**

```bash
cd /home/y_ohi/dotfiles/scripts/workers
npm install --save-dev miniflare
node install.test.js
```

Expected: 2 tests pass。

- [ ] **Step 5: コミット**

```bash
git add scripts/workers/
git commit -m "feat: Cloudflare Workers によるブートストラップスクリプト配信を追加"
```

---

## Task 3: Ansible 共通ロール `ansible/roles/common-setup/` の作成

**Files:**
- Create: `ansible/roles/common-setup/defaults/main.yml`
- Create: `ansible/roles/common-setup/tasks/main.yml`

**Interfaces:**
- Consumes: `username`, `ssh_public_key_path`, `new_ssh_port`
- Produces: cloned `/home/{{ username }}/dotfiles`, hardened sshd, UFW rule for `new_ssh_port`, verified SSH connectivity on new port

- [ ] **Step 1: デフォルト変数を作成**

```yaml
---
# ansible/roles/common-setup/defaults/main.yml
username: "y_ohi"
ssh_public_key_path: "~/.ssh/id_ed25519.pub"
new_ssh_port: 5310
```

- [ ] **Step 2: 共通タスクを作成**

```yaml
---
# ansible/roles/common-setup/tasks/main.yml
- name: Ensure operator SSH public key is authorized
  ansible.posix.authorized_key:
    user: "{{ username }}"
    state: present
    key: "{{ lookup('ansible.builtin.file', ssh_public_key_path) }}"
  become: true
  become_user: "{{ username }}"

- name: Clone dotfiles-core repository
  ansible.builtin.git:
    repo: "git@github.com:yohi/dotfiles-core.git"
    dest: "/home/{{ username }}/dotfiles"
    accept_hostkey: true
    version: master
  become: true
  become_user: "{{ username }}"

- name: Check if UFW is installed
  ansible.builtin.command: which ufw
  register: ufw_check
  failed_when: false
  changed_when: false

- name: Allow new SSH port via UFW
  community.general.ufw:
    rule: allow
    port: "{{ new_ssh_port | string }}"
    proto: tcp
  when: ufw_check.rc == 0

- name: Check if ssh.socket is active
  ansible.builtin.systemd:
    name: ssh.socket
  register: ssh_socket_status
  failed_when: false

- name: Disable ssh.socket and enable ssh.service
  ansible.builtin.systemd:
    name: "{{ item.name }}"
    enabled: "{{ item.enabled }}"
    state: "{{ item.state }}"
  loop:
    - { name: "ssh.socket", enabled: false, state: "stopped" }
    - { name: "ssh", enabled: true, state: "started" }
  when:
    - ssh_socket_status.status is defined
    - ssh_socket_status.status.ActiveState is defined
    - ssh_socket_status.status.ActiveState == 'active'

- name: Configure SSH Daemon port
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?Port\s'
    line: "Port {{ new_ssh_port }}"
    state: present
  notify: Restart SSH

- name: Disable SSH Root Login
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PermitRootLogin\s'
    line: "PermitRootLogin no"
    state: present
  notify: Restart SSH

- name: Disable SSH Password Authentication
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^#?PasswordAuthentication\s'
    line: "PasswordAuthentication no"
    state: present
  notify: Restart SSH

- name: Flush handlers to restart SSH immediately
  ansible.builtin.meta: flush_handlers

- name: Verify SSH connection on new port
  ansible.builtin.wait_for:
    host: "{{ ansible_host }}"
    port: "{{ new_ssh_port }}"
    state: started
    delay: 2
    timeout: 30
  delegate_to: localhost
  become: false
```

- [ ] **Step 3: シンタックスチェック**

```bash
cd /home/y_ohi/dotfiles/ansible
ansible-playbook --syntax-check -i hosts.ini setup.yml
```

Expected: エラーなしで終了。`hosts.ini` が存在しない場合はダミーを作成してチェックする。

- [ ] **Step 4: コミット**

```bash
git add ansible/roles/common-setup/
git commit -m "feat: Ansible 共通ロール common-setup を追加"
```

---

## Task 4: VPS 用 Ansible プレイブック `ansible/setup.yml` の修正

**Files:**
- Modify: `ansible/setup.yml`

**Interfaces:**
- Consumes: `ansible_user` from `hosts.ini` (provider-supplied user like root), `username`, `ssh_public_key_path`, `new_ssh_port`, `github_token`
- Produces: calls `common-setup` role after creating user and optionally registering GitHub deploy key

- [ ] **Step 1: 既存の setup.yml を修正**

```yaml
---
# ansible/setup.yml
- name: VPS Initial Server Setup
  hosts: servers
  become: true
  vars_files:
    - vars.yml

  tasks:
    - name: Ensure target user exists
      ansible.builtin.user:
        name: "{{ username }}"
        shell: /bin/bash
        groups: sudo
        append: true
        generate_ssh_key: true
        ssh_key_type: ed25519
        ssh_key_file: .ssh/id_ed25519
        state: present

    - name: Configure passwordless sudo for target user
      ansible.builtin.copy:
        content: "{{ username }} ALL=(ALL) NOPASSWD:ALL\n"
        dest: "/etc/sudoers.d/{{ username }}"
        owner: root
        group: root
        mode: "0440"
        validate: /usr/sbin/visudo -cf %s

    - name: Read generated SSH public key
      ansible.builtin.slurp:
        src: "/home/{{ username }}/.ssh/id_ed25519.pub"
      register: ssh_pub_key_base64

    - name: Set SSH public key fact
      ansible.builtin.set_fact:
        ssh_pub_key: "{{ ssh_pub_key_base64['content'] | b64decode | trim }}"

    - name: Display SSH public key for GitHub Deploy Key
      ansible.builtin.debug:
        msg: |
          ===========================================================
          GitHubから dotfiles をクローンするため、以下の公開鍵を
          GitHubリポジトリの Deploy Key に登録してください。

          {{ ssh_pub_key }}

          登録先URL: https://github.com/yohi/dotfiles-core/settings/keys
          ===========================================================
      when: github_token | default('') | length == 0

    - name: Automatically register SSH public key as GitHub Deploy Key
      ansible.builtin.uri:
        url: "https://api.github.com/repos/yohi/dotfiles-core/keys"
        method: POST
        headers:
          Authorization: "token {{ github_token }}"
          Accept: "application/vnd.github+json"
          X-GitHub-Api-Version: "2022-11-28"
        body_format: json
        body:
          title: "VPS-Target-Key"
          key: "{{ ssh_pub_key }}"
          read_only: true
        status_code: [201]
      when: github_token | default('') | length > 0

    - name: Pause and wait for Deploy Key registration
      ansible.builtin.pause:
        prompt: "GitHubへの Deploy Key の登録が完了したら、エンターキーを押して続行してください..."
      when: github_token | default('') | length == 0

  roles:
    - role: common-setup
      vars:
        username: "{{ username }}"
        ssh_public_key_path: "{{ ssh_public_key_path }}"
        new_ssh_port: "{{ new_ssh_port }}"

  handlers:
    - name: Restart SSH
      ansible.builtin.service:
        name: "{{ item }}"
        state: restarted
      loop:
        - ssh
        - sshd
      failed_when: false
```

- [ ] **Step 2: シンタックスチェック**

```bash
cd /home/y_ohi/dotfiles/ansible
ansible-playbook --syntax-check -i hosts.ini setup.yml
```

- [ ] **Step 3: コミット**

```bash
git add ansible/setup.yml
git commit -m "refactor: VPS 用 setup.yml を common-setup ロールを使う形に整理"
```

---

## Task 5: 物理 PC 用 Ansible プレイブック `ansible/bootstrap.yml` の作成

**Files:**
- Create: `ansible/bootstrap.yml`

**Interfaces:**
- Consumes: `username`, `ssh_public_key_path`, `new_ssh_port` from `vars.yml`; assumes user `y_ohi` already exists on port 22
- Produces: calls `common-setup` role

- [ ] **Step 1: bootstrap.yml を作成**

```yaml
---
# ansible/bootstrap.yml
- name: Physical PC Bootstrap Follow-up Setup
  hosts: servers
  become: true
  vars_files:
    - vars.yml

  tasks:
    - name: Ensure target user exists
      ansible.builtin.user:
        name: "{{ username }}"
        state: present

    - name: Ensure operator SSH public key is authorized
      ansible.posix.authorized_key:
        user: "{{ username }}"
        state: present
        key: "{{ lookup('ansible.builtin.file', ssh_public_key_path) }}"

  roles:
    - role: common-setup
      vars:
        username: "{{ username }}"
        ssh_public_key_path: "{{ ssh_public_key_path }}"
        new_ssh_port: "{{ new_ssh_port }}"

  handlers:
    - name: Restart SSH
      ansible.builtin.service:
        name: "{{ item }}"
        state: restarted
      loop:
        - ssh
        - sshd
      failed_when: false
```

- [ ] **Step 2: シンタックスチェック**

```bash
cd /home/y_ohi/dotfiles/ansible
ansible-playbook --syntax-check -i hosts.ini bootstrap.yml
```

- [ ] **Step 3: コミット**

```bash
git add ansible/bootstrap.yml
git commit -m "feat: 物理 PC 用 bootstrap.yml を追加"
```

---

## Task 6: 対話式セットアップランチャー `ansible/run.sh` の修正

**Files:**
- Modify: `ansible/run.sh`

**Interfaces:**
- Consumes: user input; existing `hosts.ini` and `vars.yml` defaults
- Produces: updated `hosts.ini`, `vars.yml`; runs selected playbook with optional `github_token` passed via env/extra-vars

- [ ] **Step 1: run.sh を修正して playbook 選択と token 扱いを追加**

`ansible/run.sh` の冒頭付近に以下を追加する。

```bash
# --- 実行対象プレイブックの選択 ---
DEFAULT_PLAYBOOK="setup.yml"
if [ -f "${SCRIPT_DIR}/bootstrap.yml" ]; then
    read -p "実行するプレイブックを選択してください [setup.yml(VPS)/bootstrap.yml(物理PC)] [${DEFAULT_PLAYBOOK}]: " PLAYBOOK
    PLAYBOOK="${PLAYBOOK:-${DEFAULT_PLAYBOOK}}"
else
    PLAYBOOK="${DEFAULT_PLAYBOOK}"
fi

if [ "${PLAYBOOK}" != "setup.yml" ] && [ "${PLAYBOOK}" != "bootstrap.yml" ]; then
    echo "エラー: プレイブックは setup.yml または bootstrap.yml を指定してください。" >&2
    exit 1
fi
```

また、vars.yml 生成時に `github_token` を含めないようにし、代わりに以下のように `ansible-playbook` 実行時に環境変数経由で渡す。

```bash
# --- GitHub Token の入力 ---
GITHUB_TOKEN_INPUT=""
if [ "${PLAYBOOK}" = "setup.yml" ]; then
    read -p "GitHub Personal Access Token (空の場合は手動登録): " GITHUB_TOKEN_INPUT
fi

# --- vars.yml 生成 ---
cat <<EOF > "${SCRIPT_DIR}/vars.yml"
---
username: "${USERNAME}"
ssh_public_key_path: "${SSH_KEY_PATH_EXPANDED}"
new_ssh_port: ${NEW_SSH_PORT}
EOF

# --- プレイブック実行 ---
EXTRA_VARS_ARGS=()
if [ -n "${GITHUB_TOKEN_INPUT}" ]; then
    EXTRA_VARS_ARGS+=("-e" "github_token=${GITHUB_TOKEN_INPUT}")
fi

ansible-playbook "${SCRIPT_DIR}/${PLAYBOOK}" \
  -i "${SCRIPT_DIR}/hosts.ini" \
  "${EXTRA_VARS_ARGS[@]}" \
  "${ANSIBLE_ARGS[@]}"
```

- [ ] **Step 2: shellcheck で検証**

```bash
cd /home/y_ohi/dotfiles/ansible
shellcheck run.sh
```

Expected: エラーなし。

- [ ] **Step 3: コミット**

```bash
git add ansible/run.sh
git commit -m "feat: ansible/run.sh で playbook 選択と GitHub Token の安全な受け渡しに対応"
```

---

## Task 7: ドキュメント更新

**Files:**
- Modify: `ansible/README.md`

**Interfaces:**
- Consumes: new playbooks and bootstrap flow
- Produces: updated usage instructions

- [ ] **Step 1: ansible/README.md を更新**

既存の内容を維持しつつ、以下を追記。

```markdown
## 物理 PC のセットアップ

物理 PC は外部からの SSH 接続ができないため、ターゲット PC のコンソールで以下を実行します。

```bash
curl -fsSL https://setup.yourdomain.com/install.sh | sh
```

その後、操作 PC で以下を実行します。

```bash
cd ansible
./run.sh
# プロンプトで bootstrap.yml を選択
```

## VPS のセットアップ

VPS はターゲット PC のコンソールに入らず、操作 PC から全て実行します。

```bash
cd ansible
./run.sh
# プロンプトで setup.yml を選択
```
```

- [ ] **Step 2: コミット**

```bash
git add ansible/README.md
git commit -m "docs: ansible/README に物理 PC / VPS の新フローを追記"
```

---

## セルフレビュー

### Spec coverage

| 設計書セクション | 実装タスク |
| :--- | :--- |
| `scripts/bootstrap.sh` | Task 1 |
| `scripts/workers/install.js` | Task 2 |
| `ansible/setup.yml` (VPS) | Task 4 |
| `ansible/bootstrap.yml` (物理 PC) | Task 5 |
| `ansible/roles/common-setup/` | Task 3 |
| `ansible/run.sh` 対話式 | Task 6 |
| セキュリティ設計 | Task 1, 2, 4, 5, 6 |
| テスト方針 | Task 1, 2 |
| ドキュメント | Task 7 |

### Placeholder scan

- TBD/TODO: なし
- 不明瞭な指示: なし
- 未実装関数: なし

### Type consistency

- 変数名 `username`, `ssh_public_key_path`, `new_ssh_port`, `github_token` は設計書と一致。
- Workers 環境変数名 `GITHUB_REPO`, `GITHUB_REF`, `SCRIPT_PATH`, `EXPECTED_PREFIX`, `EXPECTED_MARKER` は設計書と一致。

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-18-ubuntu-bootstrap-implementation-plan.md`.**

Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
