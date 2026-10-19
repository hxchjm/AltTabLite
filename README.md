# AltTabLite

轻量的 macOS Windows 式 Alt+Tab 窗口切换器，支持列表与 Cover Flow 两种样式。

要求 macOS 13 或更高版本。

## 安装

1. 从 [Releases](https://github.com/hxchjm/AltTabLite/releases) 下载 `AltTabLite-<版本>.zip` 和对应的 `.sha256` 文件。
2. （可选）校验下载文件：
   ```bash
   shasum -a 256 -c AltTabLite-<版本>.zip.sha256
   ```
3. 解压后把 `AltTabLite.app` 拖到「应用程序」文件夹。
4. 首次打开。本应用采用临时签名（ad-hoc），未经 Apple 公证，macOS 会提示无法验证开发者：
   - macOS 15 及以上：先双击打开一次并关闭提示，然后在「系统设置 → 隐私与安全性」底部点「仍要打开」，输入密码确认。
   - macOS 13–14：在 Finder 中右键应用 →「打开」→ 再点「打开」。
5. 在「系统设置 → 隐私与安全性 → 辅助功能」中允许 AltTabLite，用于监听快捷键和切换窗口。

如果以上方式无效，可以自行移除下载隔离属性（请确认安装包来自本仓库的 Releases）：

```bash
xattr -dr com.apple.quarantine /Applications/AltTabLite.app
```

## 更新

用新版本替换 `/Applications/AltTabLite.app`。由于临时签名在每次构建时都会变化，更新后通常需要重新授权：

1. 在「系统设置 → 隐私与安全性 → 辅助功能」中选中 AltTabLite，点「−」删除。
2. 重新打开 AltTabLite，按提示再次允许。

## 从源码构建

需要 Xcode 或 Command Line Tools（`xcode-select --install`）。

```bash
git clone https://github.com/hxchjm/AltTabLite.git
cd AltTabLite
CODE_SIGN_IDENTITY="-" ./build.sh
open build/AltTabLite.app
```

`build.sh` 默认使用名为 `AltTabLite Dev` 的本地签名证书；使用固定的本地证书可以避免每次重新构建后都要重新授权辅助功能。

## 发布

```bash
./release.sh
```

脚本会以临时签名构建应用，在 `dist/` 下生成 `AltTabLite-<版本>.zip` 和 `.sha256` 校验文件，把这两个文件上传到 GitHub Releases 即可。版本号来自 `Info.plist` 的 `CFBundleShortVersionString`。
