# Synopsys 2016 Docker 环境配置指南

## 服务器信息

- **服务器**: ubuntu@117.50.81.212
- **Docker镜像**: synopsys2016:0.0.0 (16.5GB)
- **工具链**: VCS L-2016.06, DC L-2016.03-SP1, Verdi L-2016.06-1, PT M-2016.12-SP1, ICC L-2016.03-SP1

## 创建容器

### 前提条件

需要一个已运行的容器（`synopsys`）提供License服务：

```bash
# 基础容器（提供License服务）- 已存在
docker run -d --name synopsys \
  --hostname lizhen \
  --entrypoint "" \
  --pid=host \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -v /home/ubuntu/workspace:/workspace \
  -v /proc:/host_proc:ro \
  synopsys2016:0.0.0 \
  /bin/bash -c '/usr/synopsys/11.9/amd64/bin/lmgrd -c /usr/local/flexlm/licenses/license.dat; sleep infinity'
```

### 创建新的工作容器

```bash
docker run -d --name synopsys_fa \
  --entrypoint "" \
  --pid=host \
  --network=container:synopsys \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  -v /home/ubuntu/fa_project:/workspace \
  -v /proc:/host_proc:ro \
  synopsys2016:0.0.0 \
  /bin/bash -c 'sleep infinity'
```

### 关键Docker参数说明

| 参数 | 说明 |
|------|------|
| `--pid=host` | 共享宿主机PID namespace，解决VCS get_proc_stat SIGSEGV |
| `--network=container:synopsys` | 共享License容器的网络，访问27000@lizhen |
| `--security-opt seccomp=unconfined` | 禁用seccomp，避免VCS系统调用被拦截 |
| `--entrypoint ""` | 覆盖镜像内置的entrypoint |

## VCS编译

### 环境变量

```bash
export SNPSLMD_LICENSE_FILE=27000@lizhen
export VCS_HOME=/usr/synopsys/vcs-L-2016.06
```

### 编译命令（关键LDFLAGS）

```bash
vcs -full64 -sverilog \
    +incdir+rtl/include \
    +define+SIMULATION \
    -timescale=1ns/1ps \
    -LDFLAGS "-Wl,--no-as-needed -Wl,--unresolved-symbols=ignore-in-shared-libs" \
    <source files> \
    -o simv_system
```

**`-LDFLAGS` 说明**：
- `-Wl,--no-as-needed`: 强制链接所有.so，解决libsnpsmalloc.so符号缺失
- `-Wl,--unresolved-symbols=ignore-in-shared-libs`: 忽略共享库间未解析符号

## 已验证的仿真结果

```
Cycles:         276100  (PASS, < 300k)
mean_abs_error: 0.013350 (PASS)
max_abs_error:  0.238281 (PASS)
>>> ALL TESTS PASSED <<<
```
