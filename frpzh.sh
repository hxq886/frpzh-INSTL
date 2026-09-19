#!/bin/bash
#安装：curl -fsSL https://raw.githubusercontent.com/hxq886/frpzh-INSTL/main/frpzh.sh -o frpzh && chmod +x frpzh && sudo mv frpzh /usr/local/bin/frpzh && frpzh
# --- 基础配置 ---
INSTALL_DIR_FRPS="/opt/frps"
INSTALL_DIR_FRPC="/opt/frpc"
FRPS_BIN="/usr/local/bin/frps"
FRPC_BIN="/usr/local/bin/frpc"
SERVICE_FRPS="frps.service"
SERVICE_FRPC="frpc.service"

# --- 下载地址配置 (方便修改) ---
FRP_RELEASE_BASE="https://github.com/hxq886/frpzh/releases/download/0.71.0"
FRP_DOWNLOAD_URL_AMD64="${FRP_RELEASE_BASE}/frp_0.71.0_linux_amd64.tar.gz"
FRP_DOWNLOAD_URL_ARM64="${FRP_RELEASE_BASE}/frp_0.71.0_linux_arm64.tar.gz"
SCRIPT_UPDATE_URL="https://raw.githubusercontent.com/hxq886/frpzh-INSTL/main/frpzh.sh"

# GitHub 加速代理列表（国内服务器自动使用）
GITHUB_PROXIES=(
    "https://gh-proxy.com/"
    "https://ghfast.top/"
    "https://mirror.ghproxy.com/"
)

# 是否使用代理（脚本启动时自动检测）
USE_PROXY=0
PROXY_PREFIX=""


# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检测服务器是否在国内，国内自动使用 GitHub 加速代理
detect_region() {
    echo -e "${YELLOW}正在检测服务器网络环境...${NC}"
    local country=$(curl -s --max-time 5 https://ipinfo.io/country 2>/dev/null || echo "")
    if [[ "$country" == "CN" ]]; then
        USE_PROXY=1
        # 测试第一个代理是否可用，不可用则换下一个
        for proxy in "${GITHUB_PROXIES[@]}"; do
            if curl -s --max-time 5 -o /dev/null "${proxy}https://raw.githubusercontent.com/torvalds/linux/master/README"; then
                PROXY_PREFIX="$proxy"
                echo -e "${GREEN}检测到国内服务器，将使用加速代理: ${PROXY_PREFIX}${NC}"
                break
            fi
        done
        if [[ -z "$PROXY_PREFIX" ]]; then
            echo -e "${YELLOW}警告: 所有加速代理均不可用，将使用直连下载${NC}"
            USE_PROXY=0
        fi
    else
        USE_PROXY=0
        echo -e "${GREEN}检测到海外服务器，使用 GitHub 直连${NC}"
    fi
}

# 根据当前环境获取加速后的下载地址
get_download_url() {
    local original_url="$1"
    if [[ $USE_PROXY -eq 1 ]]; then
        echo "${PROXY_PREFIX}${original_url}"
    else
        echo "${original_url}"
    fi
}

# 自动探测服务器架构，并选择对应类型的下载地址（结果存入 DOWNLOAD_URL）
detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            DOWNLOAD_URL=$(get_download_url "${FRP_DOWNLOAD_URL_AMD64}")
            ;;
        aarch64)
            DOWNLOAD_URL=$(get_download_url "${FRP_DOWNLOAD_URL_ARM64}")
            ;;
        *)
            echo -e "${RED}暂不支持的架构: $ARCH${NC}"
            return 1
            ;;
    esac
    echo -e "${GREEN}检测到服务器架构: ${ARCH}，使用对应架构的安装包${NC}"
}

# 检查权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误: 请使用 sudo 运行此脚本${NC}"
   exit 1
fi

# 启动时自动检测服务器区域
detect_region

# ==================== FRPS 服务端模块 ====================

install_frps() {
    echo -e "${YELLOW}--- 安装 FRPS 服务端 ---${NC}"
    
    # 1. 自动探测服务器架构并选择对应下载地址
    detect_arch || return 1

    echo "正在从 GitHub 下载 FRPS..."
    # 重新创建并清理安装目录
    rm -rf "${INSTALL_DIR_FRPS}"
    mkdir -p "${INSTALL_DIR_FRPS}"
    
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}" || return 1
    
    if command -v wget >/dev/null 2>&1; then
        wget -qO download.tar.gz "${DOWNLOAD_URL}"
    else
        curl -L -o download.tar.gz "${DOWNLOAD_URL}"
    fi
    
    # 直接解压到目标目录，使用 --strip-components=1 去掉第一层文件夹
    tar -zxvf download.tar.gz -C "${INSTALL_DIR_FRPS}" --strip-components=1
    
    # 移动可执行文件到系统目录
    cp "${INSTALL_DIR_FRPS}/frps" "${FRPS_BIN}"
    chmod +x "${FRPS_BIN}"
    
    cd /
    rm -rf "${TEMP_DIR}"

    # 2. 创建默认配置 TOML
    echo "创建配置文件: ${INSTALL_DIR_FRPS}/frps.toml"
    cat > "${INSTALL_DIR_FRPS}/frps.toml" << EOF
# ==== FRPS 服务端配置 (TOML 格式) ====

# Frp 绑定地址，默认 0.0.0.0 无需修改
bindAddr = "0.0.0.0"

# Frp 运行端口
bindPort = 2333

# Kcp 模式运行端口，需要和上面的相同
kcpBindPort = 2333

# 管理面板
webServer.addr = "0.0.0.0"
webServer.port = 8233
webServer.user = "admin"
webServer.password = "admin123456"

# HTTP 映射端口
vhostHTTPPort = 8080

# HTTPS 映射端口
vhostHTTPSPort = 4433

# Frp Token 特权密码（frpc 连接时鉴权用）
auth.method = "token"
auth.token = "JTl20EvAhg"

# 允许 frpc 绑定的端口范围
allowPorts = [
  { start = 2000, end = 3000 },
  { start = 3001, end = 4000 },
  { start = 4001, end = 5000 },
  { start = 4000, end = 50000 }
]

# 连接池与多路复用
transport.maxPoolCount = 50
transport.tcpMux = true

# 日志
log.level = "debug"
log.maxDays = 3

EOF

    # 3. 注册 Systemd 服务
    cat > "/etc/systemd/system/${SERVICE_FRPS}" << EOF
[Unit]
Description=FRP Server Service
After=network.target

[Service]
User=root
ExecStart=${FRPS_BIN} -c ${INSTALL_DIR_FRPS}/frps.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_FRPS}
    systemctl stop ${SERVICE_FRPS}
    systemctl start ${SERVICE_FRPS}
    echo -e "${GREEN}FRPS 服务端安装成功！${NC}"
    echo -e "${YELLOW}管理面板: http://服务器IP:8233 (admin/admin123456)${NC}"
}

# ==================== FRPC 客户端模块 ====================

install_frpc() {
    echo -e "${YELLOW}--- 安装 FRPC 客户端 ---${NC}"
    
    # 1. 自动探测服务器架构并选择对应下载地址
    detect_arch || return 1

    echo "正在从 GitHub 下载 FRPC..."
    # 重新创建并清理安装目录
    rm -rf "${INSTALL_DIR_FRPC}"
    mkdir -p "${INSTALL_DIR_FRPC}"
    
    TEMP_DIR=$(mktemp -d)
    cd "${TEMP_DIR}" || return 1
    
    if command -v wget >/dev/null 2>&1; then
        wget -qO download.tar.gz "${DOWNLOAD_URL}"
    else
        curl -L -o download.tar.gz "${DOWNLOAD_URL}"
    fi
    
    # 直接解压到目标目录，使用 --strip-components=1 去掉第一层文件夹
    tar -zxvf download.tar.gz -C "${INSTALL_DIR_FRPC}" --strip-components=1
    
    # 移动可执行文件到系统目录
    cp "${INSTALL_DIR_FRPC}/frpc" "${FRPC_BIN}"
    chmod +x "${FRPC_BIN}"
    
    cd /
    rm -rf "${TEMP_DIR}"

    # 2. 创建空配置 TOML
    echo "创建空配置文件: ${INSTALL_DIR_FRPC}/frpc.toml"
    cat > "${INSTALL_DIR_FRPC}/frpc.toml" << EOF
# 请在此处填写您的 frpc 配置
# serverAddr = "x.x.x.x"
# serverPort = 1210

EOF

    # 3. 注册 Systemd 服务
    cat > "/etc/systemd/system/${SERVICE_FRPC}" << EOF
[Unit]
Description=FRP Client Service
After=network.target

[Service]
User=root
ExecStart=${FRPC_BIN} -c ${INSTALL_DIR_FRPC}/frpc.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable ${SERVICE_FRPC}
    systemctl stop ${SERVICE_FRPC} 2>/dev/null || true
    # 注意：此处不启动 FRPC
    echo -e "${GREEN}FRPC 客户端安装成功！(已停止运行)${NC}"
    echo -e "${YELLOW}请修改 ${INSTALL_DIR_FRPC}/frpc.toml 配置您的服务端信息并启动服务${NC}"
}

uninstall_all() {
    read -p "确定要彻底卸载所有 frp 组件吗？(y/n): " res
    if [ "$res" = "y" ]; then
        systemctl stop ${SERVICE_FRPS} ${SERVICE_FRPC}
        systemctl disable ${SERVICE_FRPS} ${SERVICE_FRPC}
        rm -f "/etc/systemd/system/${SERVICE_FRPS}" "/etc/systemd/system/${SERVICE_FRPC}"
        rm -rf "${INSTALL_DIR_FRPS}" "${INSTALL_DIR_FRPC}" "${FRPS_BIN}" "${FRPC_BIN}"
        systemctl daemon-reload
        echo -e "${GREEN}所有组件已卸载。${NC}"
    fi
}

update_script() {
    echo -e "${YELLOW}--- 更新本脚本 ---${NC}"
    
    # 获取加速后的脚本更新地址
    local actual_script_url=$(get_download_url "${SCRIPT_UPDATE_URL}")
    echo "正在从 ${actual_script_url} 下载最新版本..."
    
    # 优先使用 wget 进行下载，因为系统可能安装了 snap 版的 curl 导致权限受限无法写入系统目录
    # 如果没有 wget，再退回使用 curl，并将其下载到当前用户的 home 目录下
    TMP_SCRIPT="$HOME/frpzh_new.sh"
    
    # 下载新脚本到临时文件
    if command -v wget >/dev/null 2>&1; then
        DOWNLOAD_CMD="wget -qO ${TMP_SCRIPT} ${actual_script_url}"
    else
        DOWNLOAD_CMD="curl -L -s -o ${TMP_SCRIPT} ${actual_script_url}"
    fi

    if $DOWNLOAD_CMD; then
        # 检查下载的文件是否包含 bash 头，简单验证是否下载成功
        if head -n 1 "${TMP_SCRIPT}" | grep -q "#!/bin/bash"; then
            # 覆盖当前脚本并赋予执行权限
            mv "${TMP_SCRIPT}" "$0"
            chmod +x "$0"
            echo -e "${GREEN}脚本更新成功！正在重启脚本...${NC}"
            sleep 2
            # 重新执行自身
            exec "$0"
        else
            echo -e "${RED}更新失败: 下载的文件格式不正确。${NC}"
            rm -f "${TMP_SCRIPT}"
        fi
    else
        echo -e "${RED}更新失败: 无法下载最新版本。${NC}"
    fi
}

# ==================== 主菜单 ====================

while true; do
    clear
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}    FRPZH 综合管理工具 (frpzh)    ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "${YELLOW}[FRP Server 服务端]${NC}"
    echo "1. 安装/更新 FRPS 服务端"
    echo "2. 修改 FRPS 配置 (TOML)"
    echo "3. 查看 FRPS 日志"
    echo "4. 重启 FRPS 服务"
    echo -e "${YELLOW}[FRP Client 客户端]${NC}"
    echo "5. 安装/更新 FRPC 客户端"
    echo "6. 修改 FRPC 配置 (TOML)"
    echo "7. 查看 FRPC 日志"
    echo "8. 重启 FRPC 服务"
    echo -e "${YELLOW}[系统管理]${NC}"
    echo "9. 查看所有服务运行状态"
    echo "10. 一键卸载所有"
    echo "11. 更新本脚本"
    echo "0. 退出"
    echo -e "${GREEN}--------------------------------${NC}"
    read -p "请选择: " opt
    case $opt in
        1) install_frps ;;
        2) nano "${INSTALL_DIR_FRPS}/frps.toml" && systemctl stop ${SERVICE_FRPS} && systemctl start ${SERVICE_FRPS} && echo "FRPS 已重启" ;;
        3) journalctl -u ${SERVICE_FRPS} -f ;;
        4) systemctl stop ${SERVICE_FRPS} && systemctl start ${SERVICE_FRPS} && echo "FRPS 已重启" ;;
        5) install_frpc ;;
        6) nano "${INSTALL_DIR_FRPC}/frpc.toml" && systemctl stop ${SERVICE_FRPC} && systemctl start ${SERVICE_FRPC} && echo "FRPC 已重启" ;;
        7) journalctl -u ${SERVICE_FRPC} -f ;;
        8) systemctl stop ${SERVICE_FRPC} && systemctl start ${SERVICE_FRPC} && echo "FRPC 已重启" ;;
        9) systemctl status ${SERVICE_FRPS} ${SERVICE_FRPC} ;;
        10) uninstall_all ;;
        11) update_script ;;
        0) exit 0 ;;
        *) echo "无效选项" ;;
    esac
    echo -e "\n按任意键返回菜单..."
    read -n 1
done
