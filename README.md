# 有梧 iOS 版 (Youwu for iOS)

梧州学院校园生活App的iOS版本，基于Flutter重写，支持课表同步、饮水设备控制、蓝牙热水器控制。

## 功能

- **自动更新的课程表**：从梧州学院新正方教务系统同步课程，显示上课时间、教师、教室及下一节课倒计时
- **饮水设备**：一键启动校园饮水机，零广告
- **洗澡服务**：通过蓝牙连接浴室热水器，一键开/关水并自动结算
- **深色模式**：跟随系统自动切换

## 技术栈

- Flutter 3.x + Dart 3.x
- Material 3
- flutter_blue_plus（蓝牙BLE）
- http（网络请求）
- shared_preferences（本地存储）
- encrypt（AES加密）
- provider（状态管理）

## 项目结构

```
lib/
├── main.dart                    # 入口
├── app.dart                     # 应用根组件
├── data/
│   ├── schedule_repository.dart # 课表同步仓库
│   ├── term_calculator.dart     # 学期周次计算
│   ├── model/                   # 数据模型
│   ├── local/                   # 本地存储、加密
│   ├── school/                  # 教务系统API
│   ├── shower/                  # 洗澡服务（API+蓝牙）
│   │   └── ble/                 # BLE协议实现
│   └── water/                   # 饮水服务API
└── ui/
    ├── main_scaffold.dart       # 底部导航主框架
    ├── schedule/                # 课表页
    ├── water/                   # 饮水页
    ├── shower/                  # 洗澡页
    ├── profile/                 # 我的页
    └── login/                   # 初次设置引导
```

## 构建iOS ipa（无需Mac）

本项目通过 **Codemagic** 云构建服务编译ipa，全程不需要Mac电脑。

### 步骤

#### 1. 注册Codemagic
访问 https://codemagic.io 注册账号（免费额度每月500分钟）。

#### 2. 推送代码到GitHub
```bash
cd youwu_ios
git init
git add .
git commit -m "init: 有梧iOS版"
git branch -M main
git remote add origin https://github.com/你的用户名/youwu_ios.git
git push -u origin main
```

#### 3. 在Codemagic中添加应用
1. 登录Codemagic → Add application
2. 选择GitHub仓库
3. 项目类型选择 **Flutter**
4. Codemagic会自动检测到 `codemagic.yaml` 配置

#### 4. 触发构建
- 推送代码到main分支会自动触发构建
- 或在Codemagic控制台手动点击 "Start new build"

#### 5. 下载ipa
构建完成后，在构建详情页的 **Artifacts** 区域下载 `youwu-ios.ipa`。

### 构建配置说明

`codemagic.yaml` 中的构建流程：
1. `flutter create --platforms=ios` — 补全iOS工程文件（因为仓库未提交ios/目录的完整工程）
2. `flutter pub get` — 获取依赖
3. `flutter build ios --release --no-codesign` — 编译iOS包（无签名）
4. 打包为ipa

> 注意：`--no-codesign` 生成的ipa需要签名后才能安装到真机。如果你有Apple开发者账号，可以在Codemagic中配置签名证书，去掉`--no-codesign`参数。

## 本地开发（Windows/Linux）

虽然不能编译iOS，但可以写代码和运行Android版本验证逻辑：

```bash
# 安装Flutter SDK后
flutter pub get
flutter run  # 连接Android设备或模拟器
```

## 与Android原版的差异

| 功能 | Android原版 | iOS版 |
|------|------------|-------|
| 教务对接 | Chaquopy + new-school-sdk (Python) | Dart原生HTTP实现 |
| 蓝牙 | Android BLE GATT | flutter_blue_plus |
| 桌面Widget | AppWidgetProvider | 暂未实现（需WidgetKit） |
| 液态玻璃效果 | backdrop + kyant.shapes | 暂未实现 |
| 密码加密 | Android Keystore | AES固定密钥（建议替换为flutter_secure_storage） |

## 已知限制

1. 教务系统登录的RSA加密为简化实现，可能需要根据梧州学院教务系统的实际公钥调整
2. 饮水服务的API网关和客户端ID需要在 `water.properties` 中配置
3. 洗澡服务对接趣智校园API，接口地址可能需要更新
4. iOS桌面Widget需要用SwiftUI + WidgetKit单独实现

## 许可证

MIT License
