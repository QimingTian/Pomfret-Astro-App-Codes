# Raspberry Pi 重置指南

清理之前的打印服务器配置，准备用于相机服务。

## 方法 1: 快速清理（推荐）

### 步骤 1: 检查当前运行的服务

```bash
# 查看所有运行的服务
sudo systemctl list-units --type=service --state=running

# 查找打印相关的服务
sudo systemctl list-units | grep -i print
sudo systemctl list-units | grep -i cups
```

### 步骤 2: 停止并禁用打印服务

```bash
# 停止 CUPS (打印服务)
sudo systemctl stop cups
sudo systemctl stop cups-browsed

# 禁用自动启动
sudo systemctl disable cups
sudo systemctl disable cups-browsed

# 确认已停止
sudo systemctl status cups
```

### 步骤 3: 卸载打印软件（可选）

```bash
# 卸载 CUPS 打印服务器
sudo apt remove --purge cups cups-browsed cups-client cups-common cups-daemon cups-filters cups-filters-core-drivers cups-ipp-utils cups-ppdc cups-server-common

# 清理依赖
sudo apt autoremove
sudo apt autoclean
```

### 步骤 4: 检查端口占用

```bash
# 查看哪些端口被占用
sudo netstat -tulpn | grep LISTEN

# 或者使用
sudo ss -tulpn
```

如果看到 8080 端口被占用，找到进程并停止它。

## 方法 2: 完全重置系统（如果方法1不够）

### 选项 A: 重新安装 Raspberry Pi OS（最彻底）

1. **备份重要数据**（如果有）
2. **下载最新的 Raspberry Pi OS**
   - 访问：https://www.raspberrypi.com/software/
   - 使用 Raspberry Pi Imager 工具
3. **重新烧录系统到 SD 卡**
4. **首次启动后配置**

### 选项 B: 清理系统但保留数据

```bash
# 1. 停止所有不必要的服务
sudo systemctl stop cups cups-browsed
sudo systemctl disable cups cups-browsed

# 2. 卸载不需要的软件包
sudo apt remove --purge cups* printer-driver-* hplip

# 3. 清理系统
sudo apt autoremove
sudo apt autoclean
sudo apt update

# 4. 检查并清理启动项
sudo systemctl list-unit-files | grep enabled
```

## 方法 3: 最小化清理（最快）

如果你只是想快速开始，可以只停止打印服务：

```bash
# 停止打印服务
sudo systemctl stop cups cups-browsed
sudo systemctl disable cups cups-browsed

# 检查 8080 端口是否可用
sudo lsof -i :8080
# 如果没有输出，说明端口可用

# 如果 8080 被占用，找到并停止那个服务
sudo systemctl stop [服务名]
```

## 验证系统状态

```bash
# 检查系统信息
uname -a
cat /etc/os-release

# 检查 Python
python3 --version

# 检查网络
hostname -I

# 检查可用端口
sudo netstat -tulpn | grep -E ':(8080|631)' 
# 631 是 CUPS 默认端口，如果看到说明打印服务还在运行
```

## 推荐：快速开始流程

如果你想最快开始，执行这些命令：

```bash
# 1. 停止打印服务
sudo systemctl stop cups cups-browsed 2>/dev/null
sudo systemctl disable cups cups-browsed 2>/dev/null

# 2. 检查系统
python3 --version
hostname -I

# 3. 更新系统
sudo apt update

# 4. 安装我们需要的依赖
sudo apt install -y python3-pip python3-numpy libusb-1.0-0

# 5. 安装 Python 包
pip3 install flask flask-cors pillow

# 6. 检查 8080 端口
sudo lsof -i :8080
# 如果显示被占用，找到进程名并停止它
```

## 常见问题

### Q: 如何查看某个端口被什么占用？

```bash
# 方法 1
sudo lsof -i :8080

# 方法 2
sudo netstat -tulpn | grep 8080

# 方法 3
sudo ss -tulpn | grep 8080
```

### Q: 如何停止占用端口的服务？

```bash
# 找到进程 ID (PID)
sudo lsof -i :8080

# 停止进程
sudo kill -9 [PID]

# 或者如果知道服务名
sudo systemctl stop [服务名]
```

### Q: 如何检查系统是否干净？

```bash
# 检查运行的服务
sudo systemctl list-units --type=service --state=running

# 检查已安装的打印相关软件
dpkg -l | grep -i print
dpkg -l | grep -i cups

# 检查端口占用
sudo netstat -tulpn
```

## 下一步

清理完成后，继续按照相机服务安装指南：
1. 设置 udev 规则
2. 配置 USB 内存
3. 运行相机服务

---

**提示：** 如果系统很乱，最简单的方法是重新安装 Raspberry Pi OS，这样会有一个干净的系统。

