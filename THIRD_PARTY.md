# 代码来源与环境依赖

| 项目 | 来源与本包位置 | 说明 |
| --- | --- | --- |
| FMQL平台及NPU | 厂商平台；01_hardware/project及ip_repo | 保留封装IP、加密/网表及相应头文件；NPU内部实现不是个人编写 |
| JFM/Procise/iCraft | 已有厂商开发环境 | 本包包含必要工程源与运行文件，不重新分发整个SDK安装目录 |
| MIPI/视频IP | Vivado2018.3 IP及既有工程配置 | 保留XCI、XCIX和既有生成输出 |
| modelzoo_utils等 | 02_board_app/source/vendor | 保留原版权/许可，作为平台应用基础 |
| verilog-ethernet | 硬件源中的third_party | 保留项目自带许可；旧模块按顶层配置使用 |
| YOLO部署模型 | 团队算法工件，02_board_app/runtime/imodel | 当前candidate_v2 JSON/RAW；个人贡献为部署、集成与优化 |
| Qwen reviewer | 团队Qwen v3代码＋本项目板端通信接入，03_control/source/host | prompt版本roi-presence-v3-20261027，服务配置以实际请求为准 |
| ActionMLP | 团队模型及特征定义，02_board_app/runtime/action | ONNX/PT为运行依赖，当前输出模拟建议 |
| NumPy、ONNX Runtime、PyUSB | runtime/action/wheelhouse及transport/vendor | 保留原发行包、元数据和许可文件 |
| ESP-AT固件 | 乐鑫ESP32-WROOM-32-AT-V3.2.1.0，04_firmware/esp32 | 已测官方factory合并镜像，按对应发布包许可使用 |

独立实验的历史README、版本和资源结论按其原日期保留。详细逐文件来源见docs/source_origins.json。涉及对外分发时按原许可及比赛要求提交厂商依赖，商业工具安装器和私有凭据不在此包中。
