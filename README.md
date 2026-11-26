# 触控板映射 · Trackpad Profiles

把触控板上的单指位置直接对应到窗口或显示器上的位置。可以为每个 App 保存不同的触控板区域。总开关和 App 的独立开关须同时开启，且该 App 位于前台，映射才会启动。

## 构建

在 macOS 14 或更新版本上，使用已配置的 Xcode 或命令行工具运行以下命令。

```sh
./build.sh
```

脚本会为当前 Mac 的架构构建 `build/Trackpad Profiles.app`，默认使用临时签名。若要在本地升级时沿用辅助功能授权，可以将钥匙串中的 Apple Development 签名身份名称或指纹写入项目根目录的 `.signing-identity`，并在后续构建中使用同一身份。也可以通过 `TRACKPAD_PROFILES_SIGN_IDENTITY` 指定签名。从临时签名换到证书签名后需要重新授权一次。 [Apple 代码签名要求](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

读取触点依赖 macOS 的私有 MultitouchSupport 框架，升级系统后可能需要重新验证。

## 使用

1. 打开 **Trackpad Profiles.app**。首次打开时 App 列表为空。
2. 点 **添加 App…** 并选择想映射的应用。可同时保存多个应用的配置。
3. 拖动预览框的角或边可以改变区域大小，拖动框内部可以移动位置。你也可以用滑块设置宽高。缩小触控板区域后，手指移动更短的距离就能覆盖同样大的目标区域。
4. 选择 **App 窗口** 或 **显示器**。窗口模式使用该 App 最大的可见窗口。显示器模式使用该窗口所在的显示器，找不到窗口时使用主显示器。需要映射到目标的一部分时，展开 **调整目标区域**。
5. 打开 **启用映射**。如果底部提示需要授权，点 **授权辅助功能…**，在系统设置允许 Trackpad Profiles。切回已添加的 App，映射就会生效。可以随时用菜单栏的触控板图标暂停或退出。

关闭设置窗口后，App 仍可继续映射。点击 Dock 图标可以重新打开设置。

在 osu!lazer 中使用时，关闭游戏设置里的 **High precision mouse**（高精度鼠标）。如果你用键盘击打，可以用触控板瞄准，用键盘 Z / X 击打。 [osu!lazer 输入设置源码](https://github.com/ppy/osu/blob/master/osu.Game/Overlays/Settings/Sections/Input/MouseSettings.cs)

单指移动到所选区域之外时，光标会停在目标相应的边缘。映射接管单指移动时，同时移动外接鼠标可能被过滤。鼠标按键、滚动和键盘输入继续由 macOS 处理。

## 许可证

项目采用 MIT 许可证。触点结构和触控板设备识别参考了 Austin Siu 的项目，原版权声明保留在 `LICENSE.txt` 中。 [Mac-trackpad-mapper](https://github.com/lokxii/Mac-trackpad-mapper)
