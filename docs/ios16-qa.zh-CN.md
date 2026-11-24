# iOS 16.6.1 兼容改造独立 QA

日期：2026-11-24（Asia/Taipei）。审查基线 `08e2db0`；验收标准先行提交 `8617b68`。本次最终复核对象是 `/private/tmp/airhand-ios16-validated-source` 的验证工作树，最终提交 SHA 由主理人记录。

## 最终结论

**QA：PASS；路由：NoOne。** 本轮独立复核没有未解决的阻塞问题。G1 本地自动验证和源码安全复核通过，可以按既定流程推送个人兼容分支构建候选 IPA。**G2 / G3：NOT RUN**；本结论不代表已编译 iOS Release 或在 iOS 16.6.1 + TrollStore 上运行。

主理人执行的完整 G1 命令退出0，日志 `/private/tmp/airhand-ios16-g1.log` 已由QA直接读取核对：

| 验证 | 结果 | 证据与限制 |
|---|---|---|
| Rust协议、链路、移动核心及进程内服务器 | 277 PASS / 0 FAIL | 151 link + 3 protocol fixture + 29 mobile + 39 proto + 8 v10 + 47 server；真实QUIC音视频、直连/回退、重连、文件、配对/篡改/重放等回归 |
| iOS C ABI宿主行为 | 4 PASS / 0 FAIL | 无效配置、指纹、句柄和内存所有权；宿主成功不等同于iOS链接成功 |
| 真实生产Swift核心逻辑 | 22 PASS / 0 FAIL | 协议8 + 手势6 + 状态/同步8，完整G1日志逐项列出；含取消释放、观察重订阅、音频代次与缓冲 |
| IPA校验器单测 | 7 PASS / 0 FAIL | 正反向覆盖最低系统、设备平台/架构、截断、Observation弱链接、权限、缺扩展和zip路径越界；不等同于真实IPA通过 |
| 合计 | **310 PASS / 0 FAIL** | 3项明确忽略：2个文档样例、1个性能基准；没有忽略核心行为用例 |

## 独立复核证据

- 独立执行IPA校验器7项单测、actionlint 1.7.12（包含官方xcode-27标签目录）、Shell语法和 `git diff --check`，全部通过。纯语法解析35个Swift生产/测试文件通过，仅作为语法证据。
- Utilities抽取与原Native尾部逐字一致；KeyboardState、SessionUIState类体除Ignored宏改名外逐字一致。宿主target直接编译生产源码allowlist，不包含SharedStore，不接触用户真实App Group数据。
- 已复核7个可观察类、6个绑定、UIKit异步重新订阅，以及实际读取状态的body、ForEach、sheet、导航目标、toolbar、Card等闭包。旧onChange、spring、MagnificationGesture、麦克风API均采用iOS16路径。未发现生产逻辑、协议、身份或权限扩大。
- Perception精确2.0.12；规范锁固定IssueReporting2.1.2和SwiftSyntax604.0.0的revision。独立核对生成工程锁与规范pins一致；将临时锁的revision改为全0时脚本退出1拒绝，规范锁未修改。
- 独立通过GitHub官方提交接口核实checkout `d23441a48e516b6c34aea4fa41551a30e30af803`（releases-v6）及upload-artifact `cf430e030ddbb5b0abf93d22962f4752f3646cd9`（v7.0.2）。新工作流只允许个人兼容分支，contents:read，不持久保存checkout凭证，无secrets、Release或高权限PR事件。候选上传依赖全部校验成功，always诊断上传单列。
- 候选源未包含私钥、证书包、IPA、profile、settings/identity等用户数据。唯一iOS/docs/.github外改动为net.rs新增证书行为测试，无生产链路修改。真实原证书可通过；替换证书和错误pin拒绝；已保存pin不被覆盖。
- 最后独立执行 `check-source-safety.py`、生成工程锁检查、diff格式和actionlint，全部退出0。安全脚本以Git的NUL分隔输出解析含空格文件名，拒绝任意生成工程、凭据及产物；主理人负向探针已实际拒绝并移除。

## 无框架宿主执行器复核

由于本机CLT缺失完整XCTest / Testing互操作组件，仅宿主CoreTests改为显式可执行测试，iOS XCTest测试保留。QA对声明和注册清单独立比对：**22个声明、22个注册、22个唯一名称，缺失0、额外0**。原测试条件均保留，测试仍调用真实生产模块。

`expect` 条件为false时必定累计失败并输出位置；每个case只在没有新增失败时计为通过；程序仅在失败数为0且全部case通过时退出0。未知媒体类型仍明确记录失败。`--probe-failure` 实际输出 `Expectation was false` 并退出1，完整G1脚本断言该退出码；未通过删测、空测试或吞错误来放行。

本机使用隔离ManifestAPI副本及已有MacOSX26.5 SDK、临时scratch避开CLT混合接口、缺失宏插件和FileProvider扩展属性/mtime问题。未修改系统工具链或iOS生产签名规则。Package宿主macOS14仅用于测试环境；iOS最低16.6保持。

## 已修问题和边界

第一轮发现的Native.swift EOF多空行及手势cancel回归缺失均已修复；两项cancel行为已在最终22项中实际通过。C ABI首轮无效host wait-window断言与既有实现契约不符，独立确认无效句柄原本返回true以避免停止编码器等待；仅修测试，生产实现未改。

IPA校验器静态审查覆盖主App/唯一广播扩展身份、精确AppGroup、ad-hoc签名、每个Mach-O设备平台/baseline arm64/最低系统不高于16.6、Observation弱链接及禁止权限/敏感文件。真正Release编译、模拟器XCTest和实际IPA静态验证仍需G2；完整UI、iOS16旧观察后端、VideoToolbox/音频硬件、ReplayKit、TrollStore安装及覆盖升级持久化仍需G3。最终交付必须分别列明这三道闸口的真实状态。
