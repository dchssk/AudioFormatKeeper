# Audio Format Keeper

A lightweight, vendor-neutral macOS menu bar app that keeps each CoreAudio output device on a format you choose.

CoreAudioの出力デバイスごとに、選択したオーディオフォーマットを維持する、ベンダー非依存の軽量メニューバーアプリです。

## Preview / 実行イメージ

![Audio Format Keeper showing the current output device and fixed audio format in the macOS menu bar](docs/images/menu-bar-preview.png)

The current output device appears on the first line, with its fixed physical or virtual format on the second line. 1段目に現在の出力デバイス、2段目に固定した物理または仮想フォーマットを表示します。

> Project status: working source and automated tests are included. The app has not yet been verified with the original SMSL USB AUDIO device, a TEAC DAC, or every third-party driver. See [Hardware verification still needed](#hardware-verification-still-needed--実機確認が必要な項目).

## 日本語

### 主な機能

- CoreAudioから出力デバイスを列挙し、永続的なデバイスUIDで識別
- 各出力ストリームについて、ドライバが公開する物理フォーマットと仮想フォーマットを別々に列挙
- サンプルレート、チャンネル数、整数/浮動小数、ビット深度、インターリーブ方式を表示
- 選択値を `~/Library/Application Support/AudioFormatKeeper/rules.json` に保存
- 次のCoreAudio変更通知を監視し、必要な場合だけ設定を復元
  - デバイスの接続・切断
  - システム既定出力の変更
  - デバイスの公称サンプルレート変更
  - 物理/仮想ストリームフォーマット変更
- ルールごとに「システム既定出力の間だけ」または「接続中は常に」を選択
- 日本語・英語表示に対応し、macOSの優先言語またはアプリ別言語設定へ自動追従
- メニューバー本体を2段表示にし、現在の出力デバイス名と固定フォーマットを常時確認可能
- メニューバーを開くと、現在レート、全固定フォーマットと適用状態を表示
- 音声データを取得・加工しないため、EQや仮想オーディオ経路を挟まない
- 常時ポーリングではなくCoreAudioのプロパティリスナーを使用

### SMSL USB AUDIOを 2ch / 32-bit整数 / 192 kHz に固定する例

1. アプリを起動し、メニューバーの波形アイコンから **Settings…** を開きます。
2. `SMSL USB AUDIO` を選びます。
3. `Output Stream 1` の **Saved physical** から、ドライバが公開した `2 ch · 32-bit signed integer · 192 kHz` を選びます。
4. 通常は **Only while system default** を選びます。アプリ固有の出力先として使う場合も常に固定したければ **Whenever connected** を選びます。
5. 仮想フォーマットも固定したい場合だけ **Saved virtual** を選びます。物理と仮想は意味が異なるため、初期状態ではどちらも勝手に保存しません。

現在Audio MIDI設定で目的の物理フォーマットになっている場合は **Save Current Physical Formats** でも保存できます。ただし、その現在値がドライバの公開候補にも存在し、かつ書き込み可能な場合に限ります。

### 表示言語

macOSの表示言語が日本語なら、メニューバー、設定画面、フォーマット表現、警告も日本語になります。英語環境では英語で表示します。アプリ単位で切り替える場合は、macOSの「システム設定」→「一般」→「言語と地域」→「アプリケーション」で Audio Format Keeper の言語を指定し、アプリを再起動してください。

### 対応フォーマットの安全な扱い

CoreAudioは、フォーマットを単純な固定値一覧ではなく `AudioStreamRangedDescription` として範囲で返すことがあります。本アプリは次の両方に含まれるサンプルレートだけを候補にします。

1. 対象ストリームの物理または仮想フォーマットが公開する範囲
2. デバイスの `kAudioDevicePropertyAvailableNominalSampleRates` が公開する範囲

保存値を適用する直前にも、現在のドライバが公開する候補へ完全なフォーマット条件を再照合します。再接続後に候補が消えた、読み取り専用になった、複数ストリームの保存サンプルレートが競合した、といった場合は設定を強制せず、警告を表示します。

### 物理フォーマットと仮想フォーマット

- **Physical**: ハードウェア側で実際に入出力するデータ形式です。
- **Virtual**: CoreAudioクライアント（アプリやIOProc）がやり取りするデータ形式です。

ドライバによっては片方が読み取り専用、候補が空、または変更に伴って他方も変化します。本アプリは両者を混同せず、書き込み可能性を個別に確認します。設定順は物理→仮想です。

### ビルドと実行

必要環境:

- macOS 13 Ventura以降
- Xcode Command Line Toolsを含むSwift 6対応環境

開発用ビルドとテスト:

```sh
swift build
swift test
```

アドホック署名したアプリバンドルを作成:

```sh
./Scripts/build-app.sh
open dist/AudioFormatKeeper.app
```

生成物は `dist/AudioFormatKeeper.app` です。一般配布には、ご自身のDeveloper IDでの署名とAppleのnotarizationが別途必要です。

### 設計

- `CoreAudioClient`: デバイス/ストリーム/候補の取得と検証済み設定の適用
- `CoreAudioMonitor`: CoreAudioプロパティ変更通知。180 msのデバウンス付き
- `AppController`: ルール、監視、適用、画面状態を統合
- `JSONRuleStore`: UID単位のルールをJSONで原子的に保存
- AppKit `NSStatusItem`: 上段のデバイス名と下段の固定フォーマットを確実に2段表示
- SwiftUI `NSPopover` + `Settings` scene: メニューバー操作パネルと設定画面
- `Assets/AppIcon.png`: 1024 pxのアイコン原画。ビルド時に全macOS解像度を含むICNSへ変換

デバイス再接続で変化し得る `AudioDeviceID` や `AudioStreamID` は保存しません。デバイスはUID、ストリームは出力ストリーム順、フォーマットは完全なASBD条件で再解決します。

### 実機確認が必要な項目

- SMSL USB AUDIOで、`2ch / 32-bit signed integer / 192 kHz` が物理候補として列挙され設定できること
- USB切断・再接続後、同一UIDとして復元できること
- Apple Music、DAW、ブラウザなどが48 kHzへ変更した場合に、対象ドライバが再設定を受け付けること
- TEACなど複数メーカーのドライバ、および複数出力ストリームを持つ機器での挙動
- 排他モードや再生中に変更を拒否するドライバでのエラー表示と、次回通知時の再試行

ドライバによって設定反映が非同期だったり、使用中は変更を拒否したりします。失敗時に未公開値を試すことはありませんが、短時間の音切れを完全に防ぐことはできません。

## English

### What it does

- Discovers CoreAudio output devices and identifies them by persistent device UID.
- Lists each output stream's driver-advertised physical and virtual formats separately.
- Shows sample rate, channel count, integer/float representation, bit depth, and interleaving.
- Stores per-device rules in `~/Library/Application Support/AudioFormatKeeper/rules.json`.
- Reacts to device reconnects, default-output changes, nominal-rate changes, and stream-format changes.
- Can enforce a rule only while the device is the system default, or whenever it is connected.
- Includes English and Japanese UI, following the macOS preferred or per-app language.
- Uses a two-line menu bar label showing the current output device and fixed format at a glance.
- Shows the current rate, all fixed formats, and match state in the expanded menu bar panel.
- Does not capture, process, resample, or route audio.
- Uses CoreAudio property listeners instead of continuous polling.

### Safety model

Before every write, a saved choice is resolved again against the formats currently advertised by the driver. Sample-rate candidates must be inside both the stream format range and the device nominal-rate range. A missing, read-only, or conflicting format is reported and skipped. Audio Format Keeper never attempts a value outside those advertised ranges.

Physical and virtual formats are intentionally independent. Physical describes the hardware-side stream; virtual describes the format used by CoreAudio clients. Some drivers expose only one as writable.

### Build

Requires macOS 13 or newer and a Swift 6-capable Xcode toolchain.

```sh
swift build
swift test
./Scripts/build-app.sh
open dist/AudioFormatKeeper.app
```

The script creates an ad-hoc-signed app at `dist/AudioFormatKeeper.app`. Public distribution still requires Developer ID signing and notarization.

### Hardware verification still needed / 実機確認が必要な項目

Automated tests cover candidate generation, range intersection, format identity, and UID-keyed persistence. This development machine can compile and test the project, but it does not prove behavior on the user's SMSL/TEAC hardware. USB reconnect behavior, driver-specific write timing, exclusive-mode refusal, and format restoration during real playback must be tested on each representative device.

## Contributing

Issues and pull requests are welcome. When reporting a driver-specific problem, include macOS version, device name, connection type, whether the rule is physical or virtual, and the warning shown by the app. Do not post a device UID if it contains a serial number you consider private.

## License

[MIT](LICENSE)
