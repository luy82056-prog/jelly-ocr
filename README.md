# Jelly 摘李

拍下纸质书页，识别文字、校对后保存成摘录。提供 iOS 和 Android 工程。

## 快速开始

- iOS 15+：用 Xcode 打开 `ios/Jelly.xcodeproj`，真机运行用自己的签名与 Bundle Identifier，首次使用时授权相机。
- Android 6.0+：用 Android Studio 导入 `android/`，选择 JDK 17 和 Android SDK 35。也可以用与 Android Gradle Plugin 8.7 兼容的 Gradle 运行 `gradle :app:assembleDebug`。

## 使用示例

用相机对准要摘录的段落，拍照后核对 OCR 结果，修正断行和错字，再保存。iOS 的识别入口由 Vision 提供，Android 使用 CameraX 和 ML Kit 中文模型。

## 代码结构

- `ios/Sources/` 包含 Swift 界面、OCR、存储和导出。
- `android/app/src/` 包含 Java 界面、相机、OCR 和本地摘录存储。

## 开发过程

[查看开发历程](DEVELOPMENT.md)

## 许可与使用范围

项目源码采用 MIT。OCR 依赖按各自许可获取。
