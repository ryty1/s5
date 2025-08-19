#!/bin/bash

# ---------------- 带动画的执行函数 ----------------
X() {
    local Y=$1
    local CMD=$2
    local O=("▖" "▘" "▝" "▗")
    local i=0

    printf "[ ] %s" "$Y"
    eval "$CMD" > >(tee /tmp/cmd_output.log) 2>&1 &
    local PID=$!

    while kill -0 "$PID" 2>/dev/null; do
        printf "\r[%s] %s" "${O[i]}" "$Y"
        i=$(( (i + 1) % 4 ))
        sleep 0.1
    done

    wait "$PID"
    local EXIT_CODE=$?
    local OUTPUT=$(< /tmp/cmd_output.log)
    rm -f /tmp/cmd_output.log

    printf "\r                       \r"
    if [[ $EXIT_CODE -eq 0 ]]; then
        printf "[\033[0;32mOK\033[0m] %s\n" "$Y"
    else
        printf "[\033[0;31mNO\033[0m] %s\n" "$Y"
        echo "$OUTPUT"
    fi
    return $EXIT_CODE
}

# ---------------- 获取用户名和域名 ----------------
U=$(whoami)
V=$(echo "$U" | tr '[:upper:]' '[:lower:]')

HOSTNAME=$(hostname)
if [[ "$HOSTNAME" == *ct8.pl* ]]; then
    DOMAIN="$V.ct8.pl"
elif [[ "$HOSTNAME" == *serv00.com* ]]; then
    DOMAIN="$V.serv00.net"
else
    echo "🚫 无法识别主机名，默认使用 $V.local"
    DOMAIN="$V.local"
fi

PY_DIR="$HOME/domains/$DOMAIN/public_python"
ENV_FILE="$PY_DIR/.env"

# ---------------- 菜单 ----------------
menu() {
    echo "———————————————————————"
    echo "请选择操作："
    echo "1) 一键安装"
    echo "2) 端口管理"
    echo "3) 配置修改"
    echo "4) 查看服务"
    echo "5) 一键卸载"
    read -p "输入序号: " choice
}

# ---------------- 一键安装 ----------------
install_service() {
    echo "开始一键安装流程..."
    echo "————————————————————————————————————————————"

    # 删除已有 PHP 域名
    PHP_DOMAIN=$(devil www list | awk 'NR>1 && $2=="php"{print $1}')
    if [[ -n "$PHP_DOMAIN" ]]; then
        X "删除 默认PHP域名 ($PHP_DOMAIN)" "devil www del \"$PHP_DOMAIN\" || true"
        if [[ -d "$HOME/domains/$PHP_DOMAIN" ]]; then
            X "删除 PHP 域名目录 ($HOME/domains/$PHP_DOMAIN)" "rm -rf \"$HOME/domains/$PHP_DOMAIN\""
        fi
    else
        echo "ℹ️ 域名列表为空，无需删除 PHP 域名"
    fi

    # 检查 Python 域名是否已存在
    EXIST_DOMAIN=$(devil www list | awk 'NR>1 && $1=="'"$DOMAIN"'" && $2=="python"{print $1}')
    if [[ -n "$EXIST_DOMAIN" ]]; then
        if [[ -d "$PY_DIR" && -f "$PY_DIR/get.py" && -f "$PY_DIR/s5.enc" ]]; then
            echo "✅ 服务已安装，无需重复安装"
            show_service
            return
        else
            echo "⚠️ 域名已存在，但目录或文件不完整，先删除重新创建"
            X "删除已存在 Python 域名 ($DOMAIN)" "devil www del \"$DOMAIN\" || true"
            if [[ -d "$HOME/domains/$DOMAIN" ]]; then
                X "删除域名目录 ($HOME/domains/$DOMAIN)" "rm -rf \"$HOME/domains/$DOMAIN\""
            fi
        fi
    fi

    # 创建 Python 域名
    X "创建 Python 域名" "devil www add \"$DOMAIN\" python /usr/local/bin/python3.11"

    # 检查端口并创建
    PORT_LIST=$(devil port list)
    PORT_COUNT=$(echo "$PORT_LIST" | awk 'NR>1{print $1}' | wc -l)
    if (( PORT_COUNT >= 3 )); then
        echo "🚫 当前已有 3 个端口，不能再创建新端口"
        read -p "按回车返回主菜单..."
        return
    fi

    S5_PORT=$(echo "$PORT_LIST" | awk 'NR>1 && $3=="s5"{print $1}')
    if [[ -n "$S5_PORT" ]]; then
        X "删除 已存在的 s5 端口 ($S5_PORT)" "devil port del tcp $S5_PORT"
    fi

    FAIL_COUNT=0
    while true; do
        PORT=$(( (RANDOM % 62977) + 1024 ))
        OUTPUT=$(devil port add tcp "$PORT" s5 2>&1)
        if echo "$OUTPUT" | grep -q -E "(Port dodany prawidłowo|Port reserved succesfully)"; then
            echo -e "[\033[0;32mOK\033[0m] 端口创建成功: $PORT"
            break
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            echo -e "[\033[0;31mNO\033[0m] 端口创建失败: $PORT (第 $FAIL_COUNT 次)"
            if (( FAIL_COUNT >= 5 )); then
                echo "🚫 连续 5 次随机端口失败，退出安装"
                read -p "按回车返回主菜单..."
                return
            fi
            sleep 1
        fi
    done

    mkdir -p "$PY_DIR"

    # 生成 .env
    SCRIPT_KEY=71a2af107e0745ae989fdf71cb23c86e2130611d0f33e71e3f3c1b9115788b3b
    read -p "请输入 用户名: " INPUT_U
    S_U=$(echo -n "$INPUT_U" | base64)
    read -p "请输入 密码: " INPUT_P
    S_P=$(echo -n "$INPUT_P" | base64)
    cat > "$ENV_FILE" <<EOF
SCRIPT_KEY=$SCRIPT_KEY
S_U=$S_U
S_P=$S_P
S_PORT=$PORT
DOMAIN=$DOMAIN
EOF
    echo "✅ .env 文件生成成功: $ENV_FILE"

    cd "$PY_DIR" || return

    # 安装依赖
    DEPS=(python-dotenv pycryptodome setproctitle)
    for pkg in "${DEPS[@]}"; do
        if python3 -m pip show "$pkg" > /dev/null 2>&1; then
            echo -e "[\033[0;32mOK\033[0m] 已安装 $pkg，跳过"
        else
            X "安装 $pkg" "pip install $pkg"
        fi
    done

    # 下载文件（失败重试3次）
    for FILE_URL in \
        "https://raw.githubusercontent.com/ryty1/s5/main/get.py" \
        "https://raw.githubusercontent.com/ryty1/s5/main/s5.enc"; do
        FNAME=$(basename "$FILE_URL")
        ATTEMPT=0
        while true; do
            wget -q -O "$FNAME" "$FILE_URL"
            if [[ $? -eq 0 ]]; then
                echo -e "[\033[0;32mOK\033[0m] 下载 $FNAME 成功"
                break
            else
                ATTEMPT=$((ATTEMPT +1))
                echo -e "[\033[0;31mNO\033[0m] 下载 $FNAME 失败 (第 $ATTEMPT 次)"
                if (( ATTEMPT >= 3 )); then
                    echo "🚫 下载 $FNAME 失败，跳过"
                    break
                fi
                sleep 1
            fi
        done
    done

    # 启动后台服务（仅在未运行时启动）
    if ! pgrep -f "python3 $PY_DIR/get.py" >/dev/null 2>&1; then
        X "启动后台服务" "nohup python3 get.py >/dev/null 2>&1 &"
    fi
    
    sleep 5

    # 安装完成后显示服务信息
    show_service
}

# ---------------- 端口管理 ----------------
port_manager() {
    while true; do
        echo "———————————————————————"
        echo "端口管理："
        echo "1) 查看端口"
        echo "2) 更换端口"
        echo "3) 删除端口"
        echo "0) 返回主菜单"
        read -p "输入序号: " p_choice

        case $p_choice in
            1)
                devil port list
                ;;
            2)
                # 删除旧端口
                OLD_PORT=$(devil port list | awk 'NR>1 && $3=="s5"{print $1}')
                if [[ -n "$OLD_PORT" ]]; then
                    X "删除旧端口 ($OLD_PORT)" "devil port del tcp $OLD_PORT"
                fi

                # 创建新端口
                FAIL_COUNT=0
                while true; do
                    NEW_PORT=$(( (RANDOM % 62977) + 1024 ))
                    OUTPUT=$(devil port add tcp "$NEW_PORT" s5 2>&1)
                    if echo "$OUTPUT" | grep -q -E "(Port dodany prawidłowo|Port reserved succesfully)"; then
                        echo -e "[\033[0;32mOK\033[0m] 新端口创建成功: $NEW_PORT"
                        sed -i "s/^S_PORT=.*/S_PORT=$NEW_PORT/" "$ENV_FILE"

                        # 精准重启 systemd-journald 相关 Python 服务
                        PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
                        if [[ -n "$PID" ]]; then
                            kill -9 $PID
                        fi
                        sleep 3
                        
                        cd "$PY_DIR" || exit
                        nohup python3 get.py >/dev/null 2>&1 </dev/null &
                        disown
                        
                        sleep 5
                        
                        echo "✅ 已重启服务"
                        break
                    else
                        FAIL_COUNT=$((FAIL_COUNT +1))
                        echo -e "[\033[0;31mNO\033[0m] 端口创建失败: $NEW_PORT (第 $FAIL_COUNT 次)"
                        if (( FAIL_COUNT >=5 )); then
                            echo "🚫 连续5次端口创建失败，返回端口菜单"
                            break
                        fi
                        sleep 1
                    fi
                done
                ;;
            3)
                PORTS=($(devil port list | awk 'NR>1{print $1}'))
                if [[ ${#PORTS[@]} -eq 0 ]]; then
                    echo "无可删除端口"
                    continue
                fi
                echo "现有端口列表:"
                for i in "${!PORTS[@]}"; do
                    echo "$((i+1))) ${PORTS[i]}"
                done
                read -p "请输入要删除的序号: " del_idx
                PORT_DEL=${PORTS[$((del_idx-1))]}
                X "删除端口 $PORT_DEL" "devil port del tcp $PORT_DEL"
                ;;
            0)
                break
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    done
}

# ---------------- 配置修改 ----------------
config_modify() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "❌ 服务未安装，先运行一键安装"
        read -p "按回车返回主菜单..."
        return
    fi

    echo "当前配置："
    cat "$ENV_FILE"

    read -p "是否修改 账号, 密码? (y/n): " modify
    if [[ "$modify" == "y" ]]; then
        read -p "请输入新的 账号: " INPUT_U
        S_U=$(echo -n "$INPUT_U" | base64)
        sed -i '' "s|^S_U=.*|S_U=$S_U|" "$ENV_FILE"

        read -p "请输入新的 密码: " INPUT_P
        S_P=$(echo -n "$INPUT_P" | base64)
        sed -i '' "s|^S_P=.*|S_P=$S_P|" "$ENV_FILE"
        
        # 精准重启 systemd-journald 相关 Python 服务
        PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
        if [[ -n "$PID" ]]; then
            kill -9 $PID
        fi
        
        sleep 3
        
        cd "$PY_DIR" || exit
        nohup python3 get.py >/dev/null 2>&1 </dev/null &
        disown
        echo "✅ 已重启服务"
    fi
    
    sleep 5

    read -p "按回车返回主菜单..."
}


# ---------------- 查看服务 ----------------
show_service() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "❌ 服务未安装"
        read -p "按回车返回主菜单..."
        return
    fi
    
    # 小工具函数，读取 .env 中的值（保留 Base64 的 '='）
    env_get() {
        sed -n "s/^$1=//p" "$ENV_FILE" | head -n1
    }

    # 检查服务是否运行 (匹配 systemd-journald 的伪装进程)
    PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
    if [[ -n "$PID" ]]; then
        echo "✅ 服务状态：运行中 (PID: $PID)"
    else
        echo "❌ 服务状态：未运行"
    fi

    # 获取公网 IP
    PUBLIC_IP=$(curl -s ip.sb)

    # 从 .env 获取端口、账号、密码并解码
    PORT="$(env_get S_PORT)"
    USER="$(env_get S_U | base64 --decode | tr -d '\r\n')"
    PASS="$(env_get S_P | base64 --decode | tr -d '\r\n')"

    echo "———————————————————————"
    echo "你的服务："
    echo "地址：$PUBLIC_IP"
    echo "端口：$PORT"
    echo "账号：$USER"
    echo "密码：$PASS"
    echo "———————————————————————"
    read -p "按回车返回主菜单..."
}

# ---------------- 一键卸载 ----------------
uninstall_service() {
    echo "开始卸载服务..."

    # 删除 Python 域名
    if devil www list | awk -v domain="$DOMAIN" 'NR>1 && $1==domain && $2=="python"{exit 0}'; then
        X "删除 Python 域名 ($DOMAIN)" "devil www del \"$DOMAIN\" || true"
        # 删除域名目录
        if [[ -d "$HOME/domains/$DOMAIN" ]]; then
            X "删除 Python 域名目录 ($HOME/domains/$DOMAIN)" "rm -rf \"$HOME/domains/$DOMAIN\""
        fi
    fi

    # 删除 s5 端口
    S5_PORT=$(devil port list | awk 'NR>1 && $3=="s5"{print $1}')
    if [[ -n "$S5_PORT" ]]; then
        X "删除 s5 端口 ($S5_PORT)" "devil port del tcp $S5_PORT"
    fi
    
    PID=$(ps -A -o pid,comm,args | grep "[p]ython3:.*systemd-journald" | awk '{print $1}')
    if [[ -n "$PID" ]]; then
        kill -9 $PID
        echo "✅ 已杀掉 PID $PID"
    fi

    echo "✅ 卸载完成"
    read -p "按回车返回主菜单..."
}


# ---------------- 主循环 ----------------
while true; do
    menu
    case $choice in
        1) install_service ;;
        2) port_manager ;;
        3) config_modify ;;
        4) show_service ;;
        5) uninstall_service ;;
        *) echo "无效选择" ;;
    esac
done
