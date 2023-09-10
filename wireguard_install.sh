#!/bin/bash

#判断系统
#if [ ! -e '/etc/redhat-release' ]; then
    #echo "The Shell Only Fit Redhat Enterprise Linux 9.x"
#exit
#fi

#if  [ -n "$(grep ' 8\.' /etc/redhat-release)" ] ;then
    #echo "The Shell Only Fit Redhat Enterprise Linux 9.x"
#exit
#fi

#更新RHEL9.0内核
update_kernel_el9(){
    
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 
    yum install -y https://www.elrepo.org/elrepo-release-9.el9.elrepo.noarch.rpm
    dnf remove -y kernel-devel
    yum --enablerepo=elrepo-kernel install -y kernel-ml
    read -p "需要重启服务器，再次执行脚本选择安装wireguard，是否现在重启 ? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "服务器 重启中..."
		reboot
	fi
}
#升级Redhat Enterprise Linux 8.x操作系统内核
update_kernel_el8(){
    
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org 
    yum install -y https://www.elrepo.org/elrepo-release-8.el8.elrepo.noarch.rpm
    yum install -y https://mirrors.aliyun.com/epel/epel-release-latest-8.noarch.rpm
    sed -i 's|^#baseurl=https://download.example/pub|baseurl=https://mirrors.aliyun.com|' /etc/yum.repos.d/epel*
    sed -i 's|^metalink|#metalink|' /etc/yum.repos.d/epel*

    dnf remove -y kernel-devel
    yum --enablerepo=elrepo-kernel install -y kernel-ml
    read -p "需要重启服务器，再次执行脚本选择安装wireguard，是否现在重启 ? [Y/n] :" yn
	[ -z "${yn}" ] && yn="y"
	if [[ $yn == [Yy] ]]; then
		echo -e "服务器 重启中..."
		reboot
	fi
}

#生成随机端口
rand(){
    min=$1
    max=$(($2-$min+1))
    num=$(cat /dev/urandom | head -n 10 | cksum | awk -F ' ' '{print $1}')
    echo $(($num%$max+$min))  
}

wireguard_update(){
    dnf update -y wireguard-tools
    echo "更新完成"
}

wireguard_remove(){
    wg-quick down wg0
    dnf remove -y wireguard-dkms wireguard-tools
    rm -rf /etc/wireguard/
    echo "卸载完成"
}

config_client(){
cat > /etc/wireguard/client.conf <<-EOF
[Interface]
PrivateKey = $c1
Address = 10.192.64.2/32
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $s2
Endpoint = $serverip:$port
AllowedIPs = 0.0.0.0/0, ::0/0
PersistentKeepalive = 25
EOF

}

#Redhat Enterprise Linux 9.2操作系统安装Wireguard
wireguard_install(){
    dnf install -y dkms gcc-c++ gcc-gfortran glibc-headers glibc-devel libquadmath-devel libtool systemtap systemtap-devel
    dnf install -y wireguard-tools
    dnf install -y wireguard-dkms
    
    systemctl enable --now systemd-resolved
    systemctl start systemd-resolved
    systemctl restart systemd-resolved

    dnf install -y qrencode
    mkdir /etc/wireguard
    cd /etc/wireguard
    wg genkey | tee sprivatekey | wg pubkey > spublickey
    wg genkey | tee cprivatekey | wg pubkey > cpublickey
    s1=$(cat sprivatekey)
    s2=$(cat spublickey)
    c1=$(cat cprivatekey)
    c2=$(cat cpublickey)
    serverip=$(curl ipv4.icanhazip.com)
    port=$(rand 10000 60000)
    eth=$(ls /sys/class/net | grep e | head -1)
    chmod 777 -R /etc/wireguard
    systemctl stop firewalld
    systemctl disable firewalld
    dnf install -y iptables-services 
    systemctl enable iptables 
    systemctl start iptables 
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -F
    service iptables save
    service iptables restart
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p
cat > /etc/wireguard/wg0.conf <<-EOF
[Interface]
PrivateKey = $s1
Address = 10.192.0.1/16 
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -I FORWARD -s 10.192.0.1/24 -d 10.192.0.1/24 -j DROP; iptables -t nat -A POSTROUTING -o $eth -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -D FORWARD -s 10.192.0.1/24 -d 10.192.0.1/24 -j DROP; iptables -t nat -D POSTROUTING -o $eth -j MASQUERADE
ListenPort = $port
DNS = 8.8.8.8
MTU = 1420

[Peer]
PublicKey = $c2
AllowedIPs = 10.192.64.2/32
EOF

    config_client
    wg-quick up wg0
    systemctl enable wg-quick@wg0
    content=$(cat /etc/wireguard/client.conf)
    echo "电脑端请下载client.conf，手机端可直接使用软件扫码"
    echo "${content}" | qrencode -o - -t UTF8
}
#添加用户
add_user(){
    echo -e "\033[37;41m给新用户起个名字，不能和已有用户重复\033[0m"
    read -p "请输入用户名：" newname
    cd /etc/wireguard/
    cp client.conf $newname.conf
    wg genkey | tee temprikey | wg pubkey > tempubkey
    ipnum=$(grep Allowed /etc/wireguard/wg0.conf | tail -1 | awk -F '[ ./]' '{print $6}')
    newnum=$((10#${ipnum}+1))
    sed -i 's%^PrivateKey.*$%'"PrivateKey = $(cat temprikey)"'%' $newname.conf
    sed -i 's%^Address.*$%'"Address = 10.192.64.$newnum\/32"'%' $newname.conf

cat >> /etc/wireguard/wg0.conf <<-EOF
[Peer]
PublicKey = $(cat tempubkey)
AllowedIPs = 10.192.64.$newnum/32
EOF
    wg set wg0 peer $(cat tempubkey) allowed-ips 10.192.64.$newnum/32
    echo -e "\033[37;41m添加完成，文件：/etc/wireguard/$newname.conf\033[0m"
    rm -f temprikey tempubkey
}
#开始菜单
start_menu(){
    clear
    echo "========================="
    echo " Intruduction：The Shell-Script Fit Redhat Enterprise Linux 9 Operation-System"
    echo " Auther：Huibai"
    echo "========================="
    echo "1. Upgrade RHEL9 Linux System Kernel(Not Necessary)"
    echo "2. Install Wireguard VPN"
    echo "3. Upgrade Wireguard VPN"
    echo "4. Uninstall Wireguard VPN"
    echo "5. Show Code"
    echo "6. Add User"
    echo "7. Upgrade RHEL8 Linux System Kernel"

    echo "0. Exit Shell"

    echo
    read -p "Please Enter The Number:" num
#数字对应程序
    case "$num" in
    	1)
	        update_kernel_el9
	    ;;
	    2)
	        wireguard_install
	    ;;
	    3)
	        wireguard_update
	    ;;
	    4)
	        wireguard_remove
	    ;;
	    5)
	        content=$(cat /etc/wireguard/client.conf)
    	        echo "${content}" | qrencode -o - -t UTF8
	    ;;
	    6)
	        add_user
	    ;;
        7)
	        update_kernel_el8
	    ;;
	    0)
	        exit 1
	    ;;
	    *)
	clear
	    echo "请输入正确数字"
	    sleep 5s
	    start_menu
	;;
    esac
}

    start_menu



