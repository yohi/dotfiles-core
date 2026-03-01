#!/bin/bash

# メモリ最適化設定スクリプト
# Ubuntu環境用のメモリ最適化設定を適用

set -euo pipefail

echo "🔧 メモリ最適化設定を開始します..."

# 現在のメモリ使用状況を表示
echo "📊 現在のメモリ使用状況:"
free -h
echo ""

# 1. システムメモリ設定の最適化
echo "⚙️  システムメモリ設定の最適化..."

# メモリ最適化設定ファイルの作成
sudo tee /etc/sysctl.d/99-memory-optimization.conf > /dev/null << 'EOF'
# メモリ最適化設定

# スワッピネス設定 (デフォルト: 60)
# 値を小さくするとスワップの使用を減らし、RAMを優先的に使用
vm.swappiness = 10

# VFSキャッシュ圧力設定 (デフォルト: 100)
# 値を小さくするとinodeとdentryキャッシュを保持
vm.vfs_cache_pressure = 50

# Dirty比率設定 (デフォルト: 20)
# ダーティページの書き込み開始点を早める
vm.dirty_ratio = 15

# Dirty背景比率設定 (デフォルト: 10)
# バックグラウンド書き込み開始点を早める
vm.dirty_background_ratio = 5

# メモリオーバーコミット設定
# 0: ヒューリスティック (デフォルト)
# 1: 常に許可
# 2: 常に拒否
vm.overcommit_memory = 0

# オーバーコミット比率 (デフォルト: 50)
vm.overcommit_ratio = 50

# カーネルの最小空きメモリ (KB)
vm.min_free_kbytes = 131072

# Out-of-Memory Killerの設定
vm.oom_kill_allocating_task = 1

# Transparent Huge Pages の設定
# kernel.mm.transparent_hugepage.enabled = madvise
EOF

echo "✅ システムメモリ設定ファイルを作成しました: /etc/sysctl.d/99-memory-optimization.conf"

# 2. ブラウザメモリ最適化設定
echo "🌐 ブラウザメモリ最適化設定..."

# Chrome用メモリ最適化フラグの設定
mkdir -p ~/.config/chrome-flags.conf.d
cat > ~/.config/chrome-flags.conf.d/memory-optimization.conf << 'EOF'
# Chrome メモリ最適化フラグ（最小・安全）
--js-flags="--max-old-space-size=4096"
--enable-low-end-device-mode
--enable-tab-audio-muting
EOF

echo "✅ Chromeメモリ最適化設定を作成しました"

# 3. システムサービス最適化
echo "⚙️  システムサービス最適化..."

# systemd設定の最適化
sudo mkdir -p /etc/systemd/system.conf.d
sudo tee /etc/systemd/system.conf.d/memory-optimization.conf > /dev/null << 'EOF'
[Manager]
# systemd メモリ最適化設定
DefaultMemoryAccounting=yes
DefaultTasksMax=15%
DefaultLimitNOFILE=65536
DefaultLimitAS=infinity
EOF

echo "✅ systemd最適化設定を作成しました"

# 4. GNOME設定最適化
echo "🖥️  GNOME設定最適化..."

# GNOME Shell メモリリーク対策
if gsettings writable org.gnome.mutter experimental-features >/dev/null 2>&1; then
  gsettings set org.gnome.mutter experimental-features "['scale-monitor-framebuffer']" || true
fi
if gsettings writable org.gnome.shell.extensions.dash-to-dock intellihide-mode >/dev/null 2>&1; then
  gsettings set org.gnome.shell.extensions.dash-to-dock intellihide-mode 'ALL_WINDOWS' || true
fi

echo "✅ GNOME設定を最適化しました"

# 設定の適用
echo "🔄 設定を適用中..."
sudo sysctl -e -p /etc/sysctl.d/99-memory-optimization.conf

echo ""
echo "✅ メモリ最適化設定が完了しました！"
echo ""
echo "📋 適用された設定:"
echo "• スワッピネス: 10 (RAMを優先使用)"
echo "• VFSキャッシュ圧力: 50 (キャッシュ保持)"
echo "• Dirty比率: 15% (早期書き込み)"
echo "• 最小空きメモリ: 128MB"
echo "• Chromeメモリ最適化フラグ"
echo "• systemd最適化設定"
echo ""
echo "🔄 再起動を推奨します。"
echo ""
echo "📊 最適化後のメモリ使用状況:"
free -h
