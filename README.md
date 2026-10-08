# edunet-openwrt

面向 OpenWrt **fw4 / nftables** 的 IPv4、IPv6 出口地址池。自动发现候选地址，逐个验证 HTTPS 出网，再按新连接随机选择源地址；支持接口变化后重建、定时恢复、系统日志和 sysupgrade 文件保留。

基于 [lbyxiaolizi/edunet](https://git.vh.gs/lbyxiaolizi/edunet) 改编，来源与授权说明见 [NOTICE.md](NOTICE.md)。本仓库包含可复现源码，不包含路由器账号、认证配置、备份或真实地址清单。

许可证：**GPLv3（GPL-3.0-only）**，见 [LICENSE](LICENSE)。

## 能做什么

- IPv4：从 WAN 私有子网的最后一个 `/23` 选择候选；WAN 更小时使用实际子网。排除网络地址、广播地址、原 WAN、网关、本机地址和 ARP 响应或状态不明确的地址，仅保留源地址 HTTPS 验证成功者。
- IPv6：在 WAN 当前全球单播 `/64` 内随机生成最多 512 个候选，默认 500；排除原地址、零 IID 和重复项，等待 DAD，再逐个验证 HTTPS。不遍历整个 `/64`，失败后也不补抽到目标数量。
- 使用独立 nftables 表，保留原 WAN 地址、原默认路由及 UCI 网络配置。IPv6 额外维护一条属于本项目的 LAN ULA 源默认路由。
- 每分钟检查一次，正常时不重扫；WAN 变化、地址缺失或主动刷新时重建。规则丢失时恢复；失败后默认等待 300 秒重试。
- 进度、失败原因、回退、重试和健康状态直接写入 LuCI 的系统日志。

**这不会增加物理链路容量，也不会把单条 TCP 连接拆到多个地址。** 是否改善聚合吞吐取决于上级网络的限速与准入策略，不能承诺提速。

## 适用条件

用于你有权分配额外地址的上级网络。ARP/DAD 只能发现探测时的冲突，无法确认离线设备、DHCP 保留地址或上级分配权限；长期使用应由上级明确预留地址。

验证环境为 OpenWrt 25.12.5 x86_64、fw4/nftables、Lua 5.1。其他版本需要自行验证。IPv4 只支持 RFC1918 私有 WAN，拒绝 WAN/LAN 重叠；IPv6 当前要求 WAN 状态中的第一个 IPv6 地址属于 `2000::/3`、前缀为 `/64`，具有链路本地网关，LAN 的第一个前缀分配为 `/48`–`/64` ULA。不支持 PPPoE、任意 PD 拓扑或所有多 WAN 场景。

需要 `lua ubus jsonfilter ip nft curl ping awk flock sha256sum logger`。`curl` 须支持 HTTPS，安装 CA 证书；`ip` 建议使用 `ip-full`。OpenWrt 基础镜像通常已有其余工具，但请以安装器检查结果为准。

```sh
# 使用 apk 的版本：缺哪个装哪个，不要混用包管理器。
apk update
apk add lua curl ca-bundle ip-full
# 使用 opkg 的版本：
# opkg update
# opkg install lua curl ca-bundle ip-full
```

## 安装与启用

在电脑上下载源码并上传到路由器。将 `OpenWrt` 替换为自己的 SSH 别名或 `root@路由器地址`：

```sh
git clone https://github.com/RenAhsAcme/edunet-openwrt.git
scp -O -r edunet-openwrt OpenWrt:/root/
ssh OpenWrt
cd /root/edunet-openwrt
sh install.sh       # IPv4，可独立安装
sh install6.sh      # IPv6，可独立安装
```

首次安装配置默认 `ENABLED=0`，安装后先核对接口和预览。升级会保留现有配置及其启用状态，所以已启用的安装会立即重建。安装器检查依赖、备份文件，注册 hotplug 和每分钟 cron，并保存所需文件到 `/etc/sysupgrade.conf`。

```sh
vi /etc/wan-ip-pool-auto.conf
vi /etc/wan-ipv6-pool-auto.conf
# 默认逻辑接口：IPv4 WAN_IF=wan，IPv6 WAN_IF=wan6，LAN_IF=lan。
/usr/sbin/wan-ip-pool-auto plan
/usr/sbin/wan-ipv6-pool-auto plan
```

**大量 WAN 别名可能使 dnsmasq 的监听文件描述符耗尽。启用大池前请阅读 [DNS 与代理注意事项](docs/troubleshooting.md)，按实际 WAN 设备设置 DNS 不监听该设备。** 本项目安装器不自动修改你的 DNS 或代理配置。

确认候选范围及上级授权后启用，需要等待一轮扫描完成：

```sh
/root/wan-ip-pool.sh apply
/root/wan-ipv6-pool.sh apply
/usr/sbin/wan-ip-pool-auto status
/usr/sbin/wan-ipv6-pool-auto status
```

两个地址族独立运行。`PARALLEL=8` 是探测并行度，**不是地址池数量**。IPv4 `/23` 最多有 510 个候选，实际成功数量可能更少；IPv6 `POOL_SIZE=500` 是一轮随机候选数，可配置 1–512。

示例：WAN `10.20.1.210/22` 的候选子网为 `10.20.2.0/23`，主机范围 `10.20.2.1`–`10.20.3.254`，其中 `.2.255` 和 `.3.0` 都是有效主机地址。IPv6 保留 WAN 的前 64 位，仅随机生成后 64 位。

## 观察、刷新、停用

LuCI → **系统 → 系统日志**，过滤 `wan-ip-pool-auto` 或 `wan-ipv6-pool-auto`，显示全部日志等级。日志存在系统环形缓冲区，不另建持久日志文件。

```sh
logread -e wan-ip-pool-auto
logread -e wan-ipv6-pool-auto
logread -f                  # 实时跟随，Ctrl-C 退出
cat /tmp/wan-ip-pool-auto/pool
cat /tmp/wan-ipv6-pool-auto/pool
nft list table ip awp_auto
nft list table ip6 awp6_auto

# 强制重新发现，旧池连接可能需要重连。
/usr/sbin/wan-ip-pool-auto refresh
/usr/sbin/wan-ipv6-pool-auto refresh

# 停用并清理本项目的运行状态。
/root/wan-ip-pool.sh stop
/root/wan-ipv6-pool.sh stop
```

`clear` 只清理当前状态，不停用 cron，停用请用 `stop`。重新启用使用 `apply`。完整卸载：`sh uninstall.sh all`；仅卸载一个地址族：`sh uninstall.sh 4` 或 `sh uninstall.sh 6`。卸载不撤销你手工修改的 dnsmasq 设置、不删除其他 cron 条目，也不删除共用 `/etc/crontabs/root` 的 sysupgrade 保留项。备份位于命令打印的 `/root/*-backup-*` 路径。

运行状态位于 `/tmp`，重启后重新发现。sysupgrade 保留配置与源码文件，但依赖软件包仍需由新固件提供或重新安装。

## 测试与实测边界

在安装了上述依赖的 OpenWrt 上，进入源码目录执行：

```sh
lua test_netcalc.lua
lua test_netcalc6.lua
sh test_logging.sh
sh test_ipv6_pool.sh
# 需要 root 和 nftables 内核支持，只做 nft -c 检查：
sh test_nftcalc.sh
sh test_nftcalc6.sh
```

生命周期测试使用临时目录和模拟网络命令；nft 测试只检查规则，不安装它们。请勿将测试结果理解为任何网络都允许这些地址。实测成果与验证限制见 [docs/results.md](docs/results.md)，实现流程见 [docs/design.md](docs/design.md)。
