# ESP32外设与接线说明

## 功能与组成

ESP32负责板端与PC之间的无线通信，承载运行控制、性能摘要、ROI图片上传和语义复核结果返回。摄像头采集及模型推理在30TAI板端完成，视频通过HDMI输出。

所需外设：ESP32-WROOM-32系列开发板、CH340 USB转TTL适配器、TX/RX/GND连接线，以及ESP开发板的USB供电线。已测设备芯片为ESP32-D0WDQ6 v1.1、4MiB Flash；AT固件标识WROOM-32。

```text
30TAI USB HOST ── CH340 USB转TTL ── UART1 ── ESP32
                                                │ Wi-Fi
                                                ▼
                                       PC热点 / 控制服务器
                                                │ 互联网
                                                ▼
                                            Qwen服务

30TAI HDMI ── 显示器或图传设备
```

## 接线

| 30TAI／转TTL侧 | ESP开发板侧 | 作用 |
| --- | --- | --- |
| 30TAI USB HOST | CH340 USB插头 | 板端访问串口适配器 |
| CH340 TXD | D16／GPIO16，AT RX | 向ESP发送AT命令与请求数据 |
| CH340 RXD | D17／GPIO17，AT TX | 接收ESP响应和网络数据 |
| CH340 GND | GND | 信号共地 |
| CH340 VCC／3V3／5V电源脚 | 不连接 | ESP通过自身USB接口供电 |
| 可靠USB电源 | ESP开发板USB口 | 为ESP供电 |

TXD与RXD交叉连接，串口信号采用3.3V逻辑。这里的USB供电方式适用于带稳压和USB接口的开发板；裸WROOM模块需要匹配的3.3V供电电路。

现有演示已使用30TAI USB为ESP开发板供电；也可使用独立USB电源。CH340负责AT通信，ESP开发板自身USB负责供电、下载和启动日志，两者用途分别识别。

GPIO16/17是本工程所用固件的AT口；开发板丝印及实际固件映射一致后按表接线。30TAI的J16保留给AN5641摄像头。

## 固件

当前已测固件为乐鑫ESP-AT v3.2.1.0（WROOM-32）。设备查询记录中的主要字段为：

```text
AT version:3.2.1.0(s-e582629 - ESP32 - Oct 22 2024 07:36:28)
Bin version:v3.2.1.0(WROOM-32)
```

使用该固件的AT指令接口，应用逻辑位于03_control/source及板端runtime/transport，无需另外编译Arduino应用。

固件文件：`04_firmware/esp32/factory_WROOM32_AT_3_2_1_uart1.bin`。来源为已测官方发布包ESP32-WROOM-32-AT-V3.2.1.0的factory合并镜像。

| 项目 | 配置 |
| --- | --- |
| 镜像大小 | 4194304 B（4MiB） |
| 合并镜像写入起始地址 | 0x0 |
| Flash模式／频率／容量 | DIO／40MHz／4MB |
| 下载接口 | ESP开发板USB对应的UART0下载口 |
| AT运行接口 | UART1，RX GPIO16、TX GPIO17 |
| 镜像SHA256 | 9a19e93bb65d60a90fc1354d1c833a1e5f0fe01c1d6ac26141578543556d2c88 |

新设备首次烧录时，使用匹配ESP32型号的下载工具和上述配置；烧录后复位，通过AT+GMR核对实际版本。已能正常响应AT并运行本工程的设备按日常启动流程使用。

## 串口与USB识别

| 参数 | 运行配置 |
| --- | --- |
| 波特率 | 921600，由服务建立会话时设置 |
| 数据格式 | 8数据位、无校验、1停止位（8N1） |
| 硬件流控 | 关闭，使用TX/RX/GND三线 |
| USB定位 | auto_usb=true，优先上次成功端口，再通过AT回应确认候选 |

服务先尝试115200、230400、460800、921600同步，再临时设置工作串口参数。正常关闭时按会话记录恢复设置。历史UART查询可能显示接近标称波特率的实际数值，运行配置以服务的921600参数为准。

板端通过PyUSB/libusb访问CH340，设备状态可显示1-1.1、1-1.2等实际USB位置；没有/dev/ttyUSB设备节点不影响此访问方式。手动串口诊断前，应先停止使用该串口的服务。

## 网络与配置

PC保持互联网连接，并启用ESP可加入的Wi-Fi热点。板端通过AT命令让ESP连接该热点，再访问PC控制服务器。

| 地址／端口 | 功能 |
| --- | --- |
| 192.168.137.1:8769 | 当前PC热点侧命令、任务和结果服务 |
| 127.0.0.1:8770 | PC本机正式控制网页 |
| 板端127.0.0.1:18765 | 视觉worker到通信服务的本机复核接口 |
| 192.168.126.49 | 当前30TAI有线SSH地址 |

ESP通过热点获取自己的IP，地址可以变化。有线SSH使用30TAI自身的eth0地址。

私有配置中的ssid、password、host、device、key需要与部署环境一致；runtime填写板端运行目录。模板见03_control/config.example.json，其中auto_usb、independent_vision、performance_telemetry分别启用自动串口识别、独立识别服务和性能上报。PC与板端使用相同设备认证key；云API key只由PC复核服务读取。

## 启动与检查

1. 按接线表连接并上电，确认电脑热点可用。
2. 启动PC服务，浏览器打开http://127.0.0.1:8770。
3. 等待网页显示ESP在线，查询设备状态及communication_usb。
4. 选择实时相机＋HDMI，保存并启动，检查帧号与性能样本更新。
5. 选择真实Qwen时，用同一事件的ROI、回复及板端接收状态检查复核链路。
6. 结束时通过网页停止检测，正常关机后再断开板端电源。

已有设备的板端通信服务可通过SSH检查：

```bash
systemctl is-active esp32-remote-control
journalctl -u esp32-remote-control -n 60 --no-pager
```

需要独立查询AT时，先在网页停止检测，再停止通信服务；AT口可查询AT、AT+GMR、AT+UART_CUR?。完成诊断后关闭串口工具并恢复服务。通信服务与独立串口工具分时访问CH340。

## 常见问题

| 现象 | 检查项 |
| --- | --- |
| USB设备不存在 | CH340插头、USB HOST位置和设备供电 |
| CH340存在但没有AT回应 | TX/RX方向、D16/D17、共地、ESP固件、串口占用 |
| AT正常但网页ESP离线 | 热点名称密码、PC热点IP、8769端口可达性及设备认证配置 |
| 端口移动后暂时离线 | 等待自动AT识别，核对网页communication_usb及服务日志 |
| Qwen回复异常 | PC互联网、真实/模拟模式、私有云配置和请求ID对应关系 |
| 服务退出码78 | 日志表示AT发送状态不明时，按记录恢复ESP状态后重启通信服务 |

固件及串口身份信息见04_firmware/esp32/firmware_info.json；控制协议、USB选择和AT会话实现见03_control/source及02_board_app/runtime/transport。
