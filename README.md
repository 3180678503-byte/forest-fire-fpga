# 森林火灾监测FPGA工程下载与运行

本提交包从GitHub固定版本下载完整工程，检查压缩包和工程文件的SHA256摘要，再解压到本地。

仓库：https://github.com/3180678503-byte/forest-fire-fpga
固定版本：v1.0.0-20261104

## 下载工程

安装Python 3.8或更新版本及WinRAR后，Windows双击“下载工程.cmd”。Linux安装Python3和unrar后也可运行。终端命令为：

```text
python download_project.py
```

脚本使用Python标准库，支持中断后重试续传。默认下载到提交包内的downloaded目录；指定位置可使用`python download_project.py --destination D:/fire_project`。已有同名工程目录会保留，请为重新下载选择新目录。网络需能访问GitHub及其Release下载服务。

## 工程内容与运行入口

完整工程包含Vivado硬件工程及IP、板端源码与运行程序、YOLO和ActionMLP模型、ESP固件、控制网页及验证报告。解压后先阅读工程README及docs中的说明。

- 硬件：01_hardware/project/ps_in.xpr，采用Vivado2018.3及既有厂商JFM/Procise流程。
- 板端：02_board_app/runtime，按docs/运行与部署.md配置开发板系统与设备。
- PC网页：03_control/start_control.py，按配置模板填写私有网络与认证配置。
- 厂商SDK、工具补丁和板端Linux环境按THIRD_PARTY.md准备。

下载脚本完成文件还原；硬件编译、板端部署和PC服务启动按工程说明分别执行。

## 仓库源码入口

source/包含便于查看的板端、控制和硬件源码；编译与部署使用Release中的完整工程目录。代码来源见THIRD_PARTY.md及完整工程的docs/source_origins.json。
