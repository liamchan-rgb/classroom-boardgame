# 免费原生App：构建、安装与续签方案

核查日期：2026-10-12。设备：2021款12.9英寸iPad Pro、iPadOS27。教师明确：纯自用、不上架、不支付苹果开发者年费、不购买会员使用TestFlight。

## 当前结论

可以采用免费Apple账号给自己的独立原生App签名、安装；免费个人签名有效期7天，需要续签。已找到SideStore及AltStore Classic路线，不以Swift Playground运行作为唯一交付方式。

验证链路为：云端macOS/Xcode构建IPA → 用免费个人账号在设备侧签名 → 安装到iPad主屏幕 → 到期前续签。现已完成v0.5的Xcode27云端编译和IPA校验；教师iPad上的签名工具、安装、启动和续签仍未实测。

## 候选比较

| 项目 | 费用／安装条件 | 续签条件 | 当前判断 |
|---|---|---|---|
| [SideStore原项目](https://github.com/SideStore/SideStore) | 免费Apple账号；官方常规流程需要首次用电脑和USB初始化 | 设备侧Wi-Fi、LocalDevVPN与签名服务；7天到期前刷新 | 适合只安装一个自用App；版本和iPadOS27行为需实测 |
| [AltStore Classic原项目](https://github.com/altstoreio/AltStore) | 支持免费账号；官方初始化流程需要电脑 | 2.3已加入Remote AltServer；配置后可以设备侧安装／刷新，官方步骤仍包含PC配对 | 可作为另一条完整独立App路线；不应使用旧资料断言每次刷新都必须用自己的电脑 |
| [SideInstaller原项目](https://github.com/FrizzleM/SideInstaller) | 作者宣称iOS/iPadOS27可全设备侧初始化；首次安装依赖公开安装页的证书和DNS配置 | 装好SideStore后仍遵循个人签名续期 | 无电脑候选，不能当成已验证的稳定安装路径 |
| [TrollStore原项目](https://github.com/opa334/TrollStore) | 利用特定老系统条件实现永久安装 | 对兼容版本不采用常规7天续签 | 官方支持范围没有iPadOS27，不适用于当前设备 |

免费个人账号有同时安装3个此类App的限制；SideStore或AltStore自己占一个名额。本项目目前只需要一个游戏App，没有必要为了名额默认增加容器方案。

## 最新状态核查

- SideStore：GitHub latest release为0.7.0-alpha，发布日期2026-09-15；发布说明指出0.6.4及更早版本受Apple服务变更影响出现503登录问题，临时版本用于修复。不盲目按旧教程安装旧版。
- AltStore：GitHub v2.3发布于2026-09-30，Remote AltServer已列入发布说明。官方FAQ的配置步骤包含“Pair with a PC”，然后使用Wi-Fi和LocalDevVPN。日常无需自己运行电脑不等于首次无需电脑。
- SideInstaller：v1.3.1，2026-10-06；原项目兼容表声称支持27 beta1至27.0.1及更新。2026-10-12读取作者安装页，显示“55 certificates, 0 currently valid”；其流程涉及DNS配置与共享签名证书。没有证据保证教师此刻可完成首次安装。
- SideStore存在iOS27的续签问题报告；已查到#1421及用户后续反馈，不能将某个问题已关闭当作所有27设备全面验证通过。

SideInstaller不是SideStore官方项目；这里只读取作者公开资料，没有安装DNS配置、使用证书或输入Apple账号。作者README中的“安全／不收集凭据”属于项目声明，本次没有完成安全审计。备选必须使用其原项目资料，不能把同名fork当成原项目。

## 无Mac的构建路线

GitHub提供macOS托管构建机，可用于编译原生App，因此教师不需要持有Mac。官方runner-images公告已提供`xcode-27`预览标签和iOS27 SDK，可作为阶段0构建候选；具体可用性和构建结果要由实际工作流验证。

构建时生成未供设备运行的IPA，随后交给SideStore／AltStore以个人账号签名。GitHub云编译与iPad本地签名是两个步骤；仅有IPA文件不能绕过设备签名要求。本阶段不把Apple账号密码或个人签名证书上传到GitHub。

费用条件：标准GitHub托管runner在公开仓库的运行分钟免费；私有仓库有GitHub Free配额。大型runner、超额用量与存储另有规则。纯自用不等于必须公开源码；仓库可见性、免费额度及构建预算需要明确，不能把云构建笼统承诺成无限永久免费。

教师随后已授权按推荐更新计划并实施。私有仓库liamchan-rgb/classroom-boardgame已完成授权和源码上传；v0.5在Xcode27真实云端构建成功，6项核心测试通过，arm64 IPA已下载并校验。免费个人签名、首次启动和续签仍待教师设备验证。详见 `../实施计划_v2.md`。

## 与课堂离线要求的关系

游戏运行、绘本导入和存档可以继续按离线目标设计；签名初始化、获取IPA和周期续签需要联网，可安排课前完成。免费7天签名不适合长期完全不联网且不维护的使用方式。自动续签只是尝试，课堂前需确认有效期和正常启动。

直接安装的原生App仍需验证外屏公开画面、备注私有、PPTX离线页面渲染、键盘、完整存档与恢复。安装工具不证明这些功能已经通过。

## 建议的最小试验

1. 在有一次电脑初始化条件时，优先验证SideStore或AltStore Classic2.3的免费个人签名。电脑可为Windows；这只是安装工具，不增加Windows版游戏，也不要求购买Mac。
2. 用真正编译的最小独立App验证首次安装、启动和一次续签；先不制作整套桌游。
3. 在同一App中测试iPadOS27正式外屏接口与电视无线显示，检查备注／后台隔离。
4. 加入小型自制PPTX和本地存档验证，再根据证据确定阶段0是否通过。

如果完全无法临时使用任何电脑，目前的全设备侧SideInstaller路线仍存在首次安装依赖和未验证条件，不给出“免费且永久可用”的保证。

## 主要来源

- [Apple免费Personal Team及7天有效期](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [SideStore官方FAQ](https://docs.sidestore.io/docs/faq)
- [SideStore官方前置条件](https://docs.sidestore.io/docs/installation/prerequisites)
- [SideStore官方安装流程](https://docs.sidestore.io/docs/installation/install)
- [SideStore0.7.0-alpha发布说明](https://github.com/SideStore/SideStore/releases/tag/0.7.0-alpha)
- [SideStore iOS27问题#1421](https://github.com/SideStore/SideStore/issues/1421)
- [AltStore2.3发布说明](https://github.com/altstoreio/AltStore/releases/tag/v2.3)
- [AltStore官方Remote AltServer配置](https://faq.altstore.io/altstore-classic/remote-altservers)
- [SideInstaller作者安装页及当前证书状态](https://sideinstaller.net/)
- [TrollStore官方支持范围](https://github.com/opa334/TrollStore)
- [GitHub Actions费用与免费条件](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
- [GitHub官方Xcode27镜像公告](https://github.com/actions/runner-images/issues/14404)
