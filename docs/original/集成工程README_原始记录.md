# AN5641＋YOLO＋HDMI＋ESP32/Qwen＋ActionMLP 集成工程

**最终演示工程已确定（2026-10-31）：日常只按[最终演示流程](最终演示流程.md)操作。** 电脑登录后控制服务与热点自动准备，开发板/ESP上电连接，直接访问http://127.0.0.1:8770选择参数并“保存并启动”，无需运行脚本。本目录脚本作为维护入口，历史工程保留归档。下方保留技术实现与验证记录。

2026-10-31。基于 `integration/an5641_yolo_qwen_esp32_hdmi_20261028` 独立复制，板端 `/home/work/an5641_full_action_20261031/board`。原工程和 BOOT 保留。视频输入仍为 AN5641→PL裁剪缩放→ImageMake→NPU PLDDR→YOLO，检测后在CPU执行DFL/NMS；显示为HDMI，ROI/Qwen为异步旁路。新加 CPU ActionMLP 软件旁路，输出仅用于屏幕和日志，不连接飞控或执行器。

动作服务独立进程以localhost UDP接收每帧检测结果，采用原动作工程的实验状态机和ONNX模型；HDMI同时显示 `ACTION SIM ... vx vy vz yaw`，`outputs/<session>/actions.jsonl` 保存完整特征和模型/门控输出。`--action-off` 可关闭旁路；默认直播HDMI启用，录制/离线分支不启用。动作日志单文件达到16MiB轮转，最多保留当前及上一份。当前状态机仍有目标丢失后 RETURN 锁定问题，未取得队友原状态机，不能把模拟 `RETURN` 看作真实返航。

## 2026-11-01 通信与检测解耦完成

已部署独立识别服务fmql-vision-esp32.service，通信重启/停用30秒/SIGKILL后恢复均保持检测运行；网页接管、重复启动保护、显式重启/停止及真实原版回退均通过。用户确认物理HDMI帧号增长、画面正常。最终确认轮6541帧、29.615软件FPS，测试结束已恢复在线待机。操作仍使用网页；回退双击“回退通信检测解耦.cmd”。[报告](validation/vision_decouple_20261101/通信检测解耦_修改与板测报告.md)。

## 已测结果

- 动作模型接口4项通过；10个合成ROI在真实HDMI运行和动作旁路并发时，本机HTTP mock返回10/10且JPEG SHA一致10/10，动作601帧、0命令，回调29.963 FPS。这是本地mock，未调用云端或经过ESP32。
- 动作开/关两轮先后各301帧：回调29.627/29.820 FPS；两轮各5次同输入六头串行参考零字节差异、HDMI缓冲各5次读回零字节差异。非相同时间输入，不据差值单独归因。
- 用户确认物理HDMI能看到 `ACTION SIM`。75秒独立轮2146帧、回调29.917 FPS；其中SEARCH 1878、CONFIRM 1、TARGET_LOST 9、RETURN 258，安全动作均0，未验证实际火焰场景下的实时非零动作。
- 现有无线管理 `Agent` 的本地启动/停止测试通过。随后启动电脑热点及mock服务、重启ESP32服务，通过真实ESP32无线链路启动/停止新工程；运行2229帧、回调29.747 FPS，动作2229帧均SEARCH、0硬件命令；2/2合成ROI经ESP32往返mock完成、2/2 JPEG SHA一致，端到端分别3343.445ms和2267.342ms。服务测试后保持active，推理进程正常退出。没有调用真实Qwen或检验真实火烟目标。

原有YOLO/DFL/NMS、ROI、HDMI actor源码以及YOLO模型与原工程逐文件一致；主程序只增加ActionShadowBridge调用与显示。模型 JSON SHA256 `16656361bfeba709b9c49a2097893afa6ee2ff93875d78fed2796bfccb0ff8ac`，RAW `33a5c6fca0f8e858103396acb9b72dc6deb1fc4b3e97bf5256dcc36281c0a89a`，动作ONNX `a6c5e5e64e1254db61d731fd7a5302fe75f92e0bbc9495f4cac0a1b64efd6502`，新主程序 `0da52fe8d4f91413c1125fa4a0bebf57aeb10811eeaa457e9299b88f12114e69`。实测证据见 `validation/` 和板端对应 `board/outputs/`。

## 运行

### 不使用ESP32：本地HDMI演示

```bash
cd /home/work/an5641_full_action_20261031/board
python3 -u run_system.py --input live --output hdmi --qwen-off --duration 60
```

脚本检测硬件和占用，自动启动/停止动作进程，`--duration 0` 持续运行，可用 Ctrl+C 停止。Qwen关闭仅用于本地诊断。读取动作日志请到对应 `outputs/<session>/actions.jsonl`。

### 无线控制和Qwen

现有 `esp32-remote-control` 配置的 `runtime` 已指向本集成版，其他字段保留；切换前私有配置已在同目录创建仅root可读的备份。该工程使用 libusb 直接访问 CH340，不能以有无 `/dev/ttyUSB*` 判断是否连接。ESP32、热点、服务启动后可用以下命令检查：

```bash
systemctl restart esp32-remote-control
systemctl --no-pager --full status esp32-remote-control
```

日常沿用电脑 `network/esp32_qwen_20261023/remote_control/打开无线控制.cmd`。`live`入口已经通过实际无线启动/停止及2次合成ROI mock往返验证。默认mock；Qwen云端需要单独配置与验证。不要同时启动旧串口桥接服务。

### 回退无线入口

停止无线控制服务后执行：

```bash
systemctl stop esp32-remote-control
python3 /home/work/an5641_full_action_20261031/switch_wireless_runtime.py --restore
systemctl start esp32-remote-control
```

回退脚本只切换已核对的`runtime`字段，保留其他配置，且仅在服务停止/failed时执行。原版工程未被覆盖。

## 构建和部署

WSL `fmql-fire-build` 使用 `source/board/runtime/CMakeLists.txt`、aarch64交叉编译器和 `D:/Project/06_shared/fmql_assets/deps` 构建 `yolo_qwen_esp32_hdmi`。`board_bundle.tar.gz` 含私有 ARM64 Python 3.8 NumPy 1.24.4 / ONNX Runtime 1.19.2 wheel；首次在新目录解包后运行 `python3 board/action/install_deps.py` 安装到 `board/action/python`，不会修改系统Python。当前板端已部署私有依赖。

## 2026-10-31 Qwen v3合入最新完整工程

Qwen v3（5992615）已合入并部署，PC无线配置同步到本工程。原1107图NPU全量一致；实时1234帧29.667FPS＋3/3原生worker无线mock；真实云端测试集4/4，台标REJECT、烟雾和壁炉CONFIRM；5次NPU参考及HDMI读回均零差异。

[完整报告](validation/qwen_v3_20261031/合并与测试报告.md)。双击本工程`启动真实Qwen无线控制.cmd`，网页Qwen保存为真实Qwen后启动；原控制入口默认mock。
