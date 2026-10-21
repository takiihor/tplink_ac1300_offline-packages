# TP-Link AC1300（Archer T3U Plus）Ubuntu 离线启用包

目标设备：USB ID `2357:0138`，芯片 **Realtek RTL8822BU**（AC1300 双频 USB 网卡）。
目标系统：**Ubuntu 24.04（kernel 6.8 generic）**，x86_64，**完全无网络**。

## 一、已在本机验证的结论

在打包机上（Ubuntu 24.04.4 / kernel 6.8.0-142-generic）实测：

| 检查项 | 结果 |
|---|---|
| USB 枚举 | `Bus 001 Device 008: ID 2357:0138 TP-Link 802.11ac NIC` |
| 内核驱动 | `rtw88_8822bu`（内核 6.8 自带，无需编译第三方驱动；模块位于 `linux-modules-extra-6.8.0-142-generic` 包内） |
| 固件 | `/lib/firmware/rtw88/rtw8822b_fw.bin`（来自 `linux-firmware`，本包已附带解包后的文件） |
| 网卡接口 | 自动生成 `wlxa829483db8c1`，MAC 前缀 `a8:29:48`（TP-Link OUI） |
| 扫描能力 | 2.4G 与 5G 均可扫描（实测看到 5GHz / 802.11ac，链接速率报至 540 Mbit/s） |
| rfkill | `phy1: Wireless LAN`，无硬/软阻断 |

结论：**该 dongle 在 Ubuntu 24.04 上可用**，且不需要安装任何第三方 DKMS 驱动；缺的通常只是固件文件（最小化/离线安装的系统经常没装全 `linux-firmware`）。

## 二、包内容

```
rtl8822bu-t3u-offline/
├── install.sh                    # 一键安装（放固件 + 补工具 + 重载驱动 + 自检）
├── check.sh                      # 只读诊断，装前装后都能跑
├── fetch-debs.sh                 # 在【有网机器】上跑，补下 linux-modules-extra 等大件
├── README.md                     # 本文件
├── sha256sums.txt                # 全部文件校验值
├── firmware/rtw88/rtw8822b_fw.bin  # RTL8822BU WiFi 固件（147 KiB，已解压为 .bin）
└── debs/                         # 仅在缺工具时才安装，24.04 桌面版一般已自带
    ├── iw_6.7-1build1_amd64.deb
    ├── wpasupplicant_2:2.10-21ubuntu0.4_amd64.deb
    ├── wireless-tools_30~pre9-16.1ubuntu2_amd64.deb
    ├── libiw30t64_30~pre9-16.1ubuntu2_amd64.deb
    └── wireless-regdb_2026.05.30-0ubuntu1~24.04.1_all.deb   # regulatory.db，决定可用信道
```

包体很小（约 1.8 MB）。**唯一可能缺的大件是 `linux-modules-extra-<内核版本>.deb`（约 110 MB）**：
桌面版 24.04 默认已安装；服务器/最小化安装可能没有。`check.sh` 第 2 节会明确告诉你缺不缺，
缺的话在能上网的机器上执行 `./fetch-debs.sh <目标机 uname -r>` 把 deb 取到 `extra-debs/` 再拷过去。

## 三、在离线 PC 上的操作步骤

1. 解压到 U 盘或直接拷到离线机器（例如 `~/t3u/`）：

   ```bash
   tar xzf rtl8822bu-t3u-offline-ubuntu24.04.tar.gz
   cd rtl8822bu-t3u-offline
   ```

2. 先跑诊断（不需要 root 也能跑大部分检查）：

   ```bash
   ./check.sh
   ```

   重点看第 1、2、3 节必须是 `[ OK ]`：内核 ≥6.7、`rtw88_8822bu` 模块存在、固件路径可写。

3. 插入 dongle，然后一键安装：

   ```bash
   sudo ./install.sh
   ```

   想先看它会做什么：`sudo ./install.sh --dry-run`；只想放固件：`sudo ./install.sh --fw-only`。

4. 脚本最后会打印接口名和扫描到的热点列表，连接：

   ```bash
   sudo nmcli device wifi connect "你的SSID" password "你的密码" ifname wlxxxxxxxxxxxx
   ```

   图形界面下也可以直接在右上角 Wi-Fi 列表里选网络。

## 四、常见故障对照

| 现象 | 原因 | 处理 |
|---|---|---|
| `check.sh` 报 `[FAIL] rtw88_8822bu not found` | 内核 <6.7，或最小化安装缺 `linux-modules-extra-<内核>` | ① GRUB 里切到已装 modules-extra 的 6.8 内核；② 用 `fetch-debs.sh` 在有网机器取 `linux-modules-extra-*.deb` 拷过去 `sudo dpkg -i`；③ 内核 <6.7 时本包无效，需改用 Realtek 官方 DKMS 驱动 |
| 接口始终不出现，`dmesg` 有 `failed to fetch rtw88/rtw8822b_fw.bin` | 固件没落到内核实际搜索路径 | `ls -l /lib/firmware/rtw88/rtw8822b_fw.bin`；`/lib/firmware` 若是指向 `/usr/lib/firmware` 的软链接则两者等价，否则把文件同样拷到 `/usr/lib/firmware/rtw88/` |
| 只能扫到 2.4G，或 5G 信道明显偏少 | 缺 `regulatory.db` / 国家码未设 | 装包内 `debs/wireless-regdb_*.deb`，再 `sudo iw reg set CN`（按所在地区填写） |
| `lsusb` 看不到 `2357:0138` | USB 口/供电/延长线问题 | 换直插的 USB 3.0 口，去掉 hub |
| 扫描不到 5G 或频繁断连 | 电源管理 / 信号弱 | `sudo iwconfig wl… power off`；或 `sudo modprobe -r rtw88_8822bu && sudo modprobe rtw88_8822bu` |
| `rfkill` 显示 Soft blocked | 软件屏蔽 | `sudo rfkill unblock all` |
| 连上但无法上网 | DHCP/路由问题，与网卡无关 | `nmcli device status`、`journalctl -u NetworkManager` |

## 五、注意 / 未覆盖项

- 本包**不含第三方 DKMS 驱动源码**，只覆盖内核 ≥6.7（Ubuntu 24.04 的 6.8 / HWE 内核）路径。
- `debs/` 依赖的基础库（`libc6`、`libnl-3-200`、`libssl3t64` 等）在 Ubuntu 24.04 基础系统里都有，未单独打包；若在非 Ubuntu 24.04 的发行版上装 deb 可能失败。
- 该 AC1300 dongle 只有 Wi-Fi 功能，**不带蓝牙**，所以没有打包 `rtl_bt` 固件。
- dongle 走的是 **USB 2.0** 总线（`lsusb -t` 显示 480M），所以实际吞吐上限约 300~400 Mbps，达不到 867 Mbps 的空口标称值；`nmcli` 列表里的 540 Mbit/s 是 AP 侧支持速率，不代表本机链路速率。
- 安装脚本只改三处：`/lib/firmware/rtw88/`、`dpkg -i` 缺的工具/regdb 包、dongle 的驱动绑定；不会动网络配置、不写 udev 规则、不改 GRUB。

## 六、重启后不稳定：持久化电源管理修复

2026-09-30 在本机 Ubuntu 24.04.5、kernel `7.0.0-34-generic` 的检查结果：
驱动和固件在开机时正常加载，`PolyUWLAN` 自动连接并取得 DHCP 地址。
本次和上次启动的内核日志都出现 `firmware failed to leave lps state`，
且 `iw dev wlxa829483db8c1 get power_save` 显示 `on`。
这表明存在固件退出省电状态失败的问题；不需要重新安装第三方驱动。

持久修复脚本（与原离线固件安装器分开运行）：

```bash
sudo bash ./fix-persistence.sh
```

脚本写入以下设置，并更新已安装内核的 initramfs：

- `/etc/modprobe.d/90-tplink-ac1300.conf`：`rtw88_core disable_lps_deep=Y`。
- `/etc/NetworkManager/conf.d/90-tplink-ac1300.conf`：仅对 `rtw88_8822bu` 驱动默认关闭 Wi-Fi 省电。
- `/etc/udev/rules.d/90-tplink-ac1300.rules`：仅对 USB `2357:0138` 设置 `power/control=on`。

之前已存在的同名配置文件备份到 `/var/lib/tplink-ac1300-fix/<时间>/`。
脚本也关闭当前网卡的省电，不会自动重启系统。

本机还已保存以下连接设置：`PolyUWLAN` 和 `Wi-Fi.HK via PolyU` 的
`802-11-wireless.powersave=2`；`PolyUWLAN` 的 `connection.autoconnect=yes`、
`connection.autoconnect-retries=0`（持续重试）和 `connection.autoconnect-priority=10`。
这些连接级设置跨重启生效，且优先于 NetworkManager 的默认配置。

重启后检查：

```bash
nmcli device status
iw dev wlxa829483db8c1 get power_save
cat /sys/module/rtw88_core/parameters/disable_lps_deep
journalctl -b -k --no-pager | rg 'rtw.*(fail|error)'
```

预期网卡为 `connected`，省电为 `off`，深度省电禁用参数为 `Y`。
如需恢复，移除脚本创建的三个配置文件（若有旧文件则恢复备份），然后
`sudo update-initramfs -u -k all` 并重启。
连接设置原值为：两个 Wi-Fi 配置的省电值 `0`，`PolyUWLAN` 的重试值 `-1`、优先级 `0`。
