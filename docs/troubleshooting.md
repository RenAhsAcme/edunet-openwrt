# DNS、代理与日志排查

## 大地址池与 dnsmasq

dnsmasq 可能随临时 WAN 地址绑定大量 UDP/TCP 监听套接字。现场约 500 个 IPv4 地址时出现 DNS 超时与 REFUSED；限制 WAN 监听后恢复。文件描述符耗尽是结合监听数与修复结果的推断，未取得故障瞬间完整计数。

若路由器只为 LAN/本机提供 DNS，可在启用前按实际 WAN 设备增加排除。以下只适用于你确认该设备不需要对外提供 DNS 的情况；它会修改 dhcp 配置并重启 dnsmasq：

```sh
cp /etc/config/dhcp /root/dhcp-before-edunet
wan_dev=$(ubus call network.interface.wan status | jsonfilter -e '@.l3_device')
test -n "$wan_dev" || exit 1
uci -q del_list dhcp.@dnsmasq[0].notinterface="$wan_dev" || :
uci add_list dhcp.@dnsmasq[0].notinterface="$wan_dev"
uci commit dhcp
/etc/init.d/dnsmasq restart
nslookup www.baidu.com 127.0.0.1
```

多 WAN 或 WAN6 使用不同设备时逐一核对；多个 dnsmasq 实例时选择正确配置节。撤销**本次新增**的排除项：

```sh
uci del_list dhcp.@dnsmasq[0].notinterface="$wan_dev"
uci commit dhcp
/etc/init.d/dnsmasq restart
```

如果此排除项原本已经存在，不要撤销它。上述备份为单次操作示例，请自行避免覆盖既有备份。复现网络配置时不要直接覆盖别人或自己的完整 dhcp 配置。

## HTTPS 探测失败

先验证原 WAN 出网、DNS、CA 证书和设备时间。日志会标明原 WAN 检查或候选阶段。只有源绑定 HTTPS 成功才入池；失败可以来自上级准入、地址冲突、目标限频、DNS、TLS 或代理规则，不能简单等同“地址已占用”。

默认探测目标 `https://www.baidu.com/` 可由 root 在两个配置文件中改为允许访问的 HTTPS 目标。用 `--connect-to` 固定本轮目标地址不会关闭证书验证，参见 [curl 文档](https://curl.se/docs/manpage.html#--connect-to)。

存在透明代理时必须确认探测走直连，否则代理可能掩盖候选实际出网能力。IPv6 引擎在检测到 OpenClash IPv6 output 链时，要求目标命中其 `china_ip6_route` 且不命中 `china_ip6_route_pass`；不满足便停止构建。此检查依赖对应 OpenClash 规则布局，不覆盖所有代理实现。IPv4 没有通用代理路径判定，请自行核对探测目标规则。

本项目不修改 OpenClash 规则、Tailscale DNS 偏好或全局路由策略。

## MiniEAP 在系统日志中看不到

```sh
logread -e minieap
logread -f
```

LuCI 先取消严重程度/设施筛选、反向匹配，使用小写 `minieap`。procd 转发 stdout/stderr 时，程序文本含 `[E]` 也可能记录为 `daemon.info`，仅筛错误等级会漏掉它。

核对 `/etc/init.d/minieap` 的 procd stdout/stderr 转发和 MiniEAP 配置中的 daemon/file 输出方式，不要打印包含认证密码的整份配置。确需修改时请先按你所用包版本检查启动脚本并备份。程序没有输出、没有成功安排心跳，或旧日志被覆盖时，调整 LuCI 过滤条件也不会生成新日志。

## 停用与恢复

优先使用对应 `/root/wan-ip-pool.sh stop`、`/root/wan-ipv6-pool.sh stop`，避免手工删除全局规则或重启整个网络。卸载器仅删除本项目固定路径与标记任务。升级回退请先停用池，再从安装器打印的备份恢复对应文件；重新启用后会重新发现地址。
