#!/bin/bash

# 判断系统
if [[ ! -e /etc/issue ]] || [[ ! $(cat /etc/issue) == "Ubuntu 20.04"* ]]; then
  echo "只适用Ubuntu 20.04"
  exit 1
fi

# 判断用户
if [[ $(whoami) != "root" ]]; then
  echo "请以root用户执行"
  exit 2
fi

read -s -n1 -p "是否修改为清华源? [y/N]" B_UPDATE_APT_SOURCES && echo $B_UPDATE_APT_SOURCES
read -s -n1 -p "是否修改SSH设置? [y/N]" B_UPDATE_SSH_CONFIG && echo $B_UPDATE_SSH_CONFIG

case $B_UPDATE_SSH_CONFIG in
[yY])
  portRead() {
    read -p "请输入ssh端口 [default: 322]: " P_SSH_PORT
    portCheck
  }
  portCheck() {
    if [[ ! -n $P_SSH_PORT ]]; then
      P_SSH_PORT=322
    fi

    P_SSH_PORT=$(echo -e $P_SSH_PORT | sed -r 's/0*([0-9])/\1/')

    expr $P_SSH_PORT + 1 >/dev/null 2>&1
    if [[ $? -ne 0 ]] || [[ $P_SSH_PORT -lt 0 || $P_SSH_PORT -gt 65535 ]]; then
      portWarn
    fi
  }
  portWarn() {
    echo "端口格式错误! "
    portRead
  }

  portRead

  read -s -n1 -p "是否禁止密码登录? [y/N]" P_SSH_DENY_PASSWORD && echo $P_SSH_DENY_PASSWORD
  # 编辑ssh公钥
  read -s -n1 -p "准备编辑ssh公钥(按任意键继续, Ctrl + C 退出)"
  vi ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys

  case $P_SSH_DENY_PASSWORD in
  [yY])
    if [[ $(grep -o ssh-rsa ~/.ssh/authorized_keys | wc -l) == 0 ]]; then
      echo "未添加SSH公钥, 不能禁止密码登录!"
      P_SSH_DENY_PASSWORD="n"
    fi
    ;;
  esac
  ;;
esac

# 修改apt源
case $B_UPDATE_APT_SOURCES in
[yY])
  cp -b /etc/apt/sources.list /etc/apt/sources.list.mewbak
  echo "# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-security main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-security main restricted universe multiverse

# 预发布软件源，不建议启用
# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-proposed main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-proposed main restricted universe multiverse
" >/etc/apt/sources.list

  ;;
esac

# 更新
apt-get update && apt-get -y dist-upgrade

# 修改sshd_config
case $B_UPDATE_SSH_CONFIG in
[yY])
  config_file="/etc/ssh/sshd_config"

  cp -b $config_file $config_file.mewbak

  echo "" >>$config_file

  sed -i "/^Port /d" $config_file
  echo "Port $P_SSH_PORT" >>$config_file

  sed -i "/^Protocol /d" $config_file
  echo "Protocol 2" >>$config_file

  sed -i "/^LogLevel /d" $config_file
  echo "LogLevel INFO" >>$config_file

  sed -i "/^AddressFamily /d" $config_file
  echo "AddressFamily inet" >>$config_file

  sed -i "/^PermitRootLogin /d" $config_file
  sed -i "/^PasswordAuthentication /d" $config_file
  case $P_SSH_DENY_PASSWORD in
  [yY])
    echo "PermitRootLogin prohibit-password" >>$config_file
    echo "PasswordAuthentication no" >>$config_file
    ;;
  *)
    echo "PermitRootLogin yes" >>$config_file
    echo "PasswordAuthentication yes" >>$config_file
    ;;
  esac

  sed -i "/^PermitEmptyPasswords /d" $config_file
  echo "PermitEmptyPasswords no" >>$config_file

  sed -i "/^ChallengeResponseAuthentication /d" $config_file
  echo "ChallengeResponseAuthentication no" >>$config_file

  sed -i "/^UsePAM /d" $config_file
  echo "UsePAM no" >>$config_file

  sed -i "/^X11Forwarding /d" $config_file
  echo "X11Forwarding yes" >>$config_file

  sed -i "/^PrintMotd /d" $config_file
  echo "PrintMotd no" >>$config_file

  sed -i "/^MaxAuthTries /d" $config_file
  echo "MaxAuthTries 4" >>$config_file

  sed -i "/^ClientAliveInterval /d" $config_file
  echo "ClientAliveInterval 600" >>$config_file

  sed -i "/^ClientAliveCountMax /d" $config_file
  echo "ClientAliveCountMax 2" >>$config_file

  systemctl restart sshd
  ;;
esac

# 防火墙
iptables -F

echo y | ufw reset

ufw allow $P_SSH_PORT/tcp
ufw default deny
echo y | ufw enable

# 安装Docker
apt-get install -y docker.io
echo "{
  \"exec-opts\": [
    \"native.cgroupdriver=systemd\"
  ]
}
" >/etc/docker/daemon.json

# 设置中文
locale-gen zh_CN.UTF-8
if [[ $(grep -o "export LANG=" /etc/profile | wc -l) == 0 ]]; then
  echo "" >>/etc/profile
  echo "export LANG=zh_CN.UTF-8" >>/etc/profile
  source /etc/profile
fi

