# 部署 Kubernetes 集群
本文档介绍如何使用 Sealos 配置并部署 Kubernetes 集群。

## 修改 cluster.yaml 文件
提供一个使用 Sealos 部署 Kubernetes 集群的模板文件，需要根据实际情况修改配置。

* 修改 `master` 和 `node` 节点的 IP 地址 
* 修改容器数据存储目录 `criData`, 对应 containerd 的 `root` 目录
* 默认 registry 部署在第一个 master 节点上，如果要部署高可用的 registry，可以指定多个 node 的角色为 registry，如：
  ```yaml
   - ips:
   - 192.168.0.2:22
   - 192.168.0.3:22
   - 192.168.0.4:22
   roles:
   - master
   - registry
   - amd64
  ```

## 修改 `/var/lib/sealos` 默认目录存储位置
若需修改默认的存储位置，可以设置 `SEALOS_DATA_ROOT` 环境变量，然后运行 sealos 命令。建议将这个环境变量设置为全局的。
  ```shell
  export SEALOS_DATA_ROOT=/data/sealos 
  ```

## 修改 Sealos 镜像数据和状态的存储路径
在使用 Sealos 集群时，可能需要改变默认的镜像数据存储路径和状态数据的存储路径。默认情况下，这些数据被存储在 `/etc/containers/storage.conf` 文件定义的位置。

1. 查看当前存储配置

   首先，我们可以使用下面的命令来查看当前的镜像存储配置：

   ```bash
   sealos images --debug
   ```

   这个命令会打印出包含当前存储配置的文件，例如：

   ```bash
   2023-06-07T16:27:02 debug using file /etc/containers/storage.conf as container storage config
   REPOSITORY   TAG   IMAGE ID   CREATED   SIZE
   ```

2. 修改镜像数据存储路径

   如果你希望更改镜像数据的存储路径，你可以编辑 `/etc/containers/storage.conf` 文件。在这个文件中，找到并修改 graphroot 字段设置为新的路径。例如：

   ```bash
   vim /etc/containers/storage.conf
   ```

   在编辑器中，将 graphroot 字段的值修改为你希望的新路径。

3. 修改状态数据存储路径

   Sealos 同样提供了状态数据存储路径的设置。在同样的配置文件 `/etc/containers/storage.conf` 中，找到并修改 runroot 字段为新的路径。

   通过以上步骤，你可以将 Sealos 集群的镜像数据和状态数据保存到新的地址。每次运行 Sealos 命令时，它都将使用你在 graphroot 和 runroot 中设置的新路径来分别存储镜像数据和状态数据。