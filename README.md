# push docker images
使用 `Github Actions` 或自建服务器，将任意可访问镜像同步到任意目标仓库

# 使用方法
## 1. 自建服务器部署
- 克隆仓库到可以直接拉取镜像的服务器上面，然后根据脚本帮助配置运行即可 
- 详细配置查看脚本帮助说明
    ```ini
    Usage: docker-image-pusher.sh [-h] [-c images_file] [-s source_tag] [-t target_tag] [-e environment]

    Options:
    -h                                  展示帮助文档并退出.
    -c images_file                      指定同步配置文件, 默认 ./images.ini.
    -s source_tag                       单镜像同步时，指定源镜像，支持任意 Registry 地址
    -t target_tag                       单镜像同步时，指定目标镜像，支持任意 Registry 地址
    -e environment                      指定环境变量, 用以覆盖内置变量(key=value,key=value)

    Image_file:
        配置文件格式: 
            源镜像=目标镜像1,目标镜像2,目标镜像3
        配置文件示例:
            nginx=base/nginx
            registry.example.com/team/nginx:1.27=harbor-a.example.com/base/nginx:1.27,harbor-b.example.com/base/nginx:1.27
    Source_tag:
        源镜像, 支持 Docker Hub / 私有仓库 / 任意完整镜像地址
            - nginx
            - docker.io/library/nginx:latest
            - registry.example.com/team/nginx:1.27
    Target_tag:
        目标镜像支持两种形式
            - base/nginx
            - harbor.example.com/base/nginx:latest
        如果只写 base/nginx，会自动拼接 PRIVATE_REGISTRY_URLS 中的每个仓库地址
    Result:
        批量模式下，单个镜像失败不会中断后续同步
        脚本结束时会输出成功/失败汇总；若存在失败项，退出码为非 0
    Environment:
        所有支持的参数，均可以通过系统环境变量进行传递。(优先级: 参数指定 > -e 指定 > 系统环境变量 > .env > 默认值)
    系统变量:
        LOG_LEVEL                       日志级别, 默认 INFO(INFO/WARN/DEBUG/ERROR)
        IMAGES_FILE                     指定同步的配置文件, 默认 ./images.ini
        HUB_IMAGE_TAG                   指定同步的源镜像
        NEW_IMAGE_TAG                   指定同步的目标镜像
        IMAGES_CLEAN_FLAG               是否清理镜像, 默认 1 (1: 每次推送后立即清理, 0: 不清理)
        PRIVATE_REGISTRY_URLS           指定私有镜像仓库地址, 多个地址用 '|' 分隔, 默认 ''
        PRIVATE_REGISTRY_USERNAME       指定私有镜像仓库的登陆用户名, 多个用 '|' 分割，需要遵循 PRIVATE_REGISTRY_URLS 变量配置顺序
        PRIVATE_REGISTRY_PASSWORD       指定私有镜像仓库的登陆密码, 多个用 '|' 分割，需要遵循 PRIVATE_REGISTRY_URLS 变量配置顺序
        SOURCE_REGISTRY_URLS            指定源镜像仓库地址, 非必填; 支持多个地址用 '|' 分隔; 留空时默认按 Docker Hub 处理
        SOURCE_REGISTRY_USERNAME        指定源镜像仓库用户名, 非必填; 支持多个用 '|' 分隔，需要遵循 SOURCE_REGISTRY_URLS 变量配置顺序
        SOURCE_REGISTRY_PASSWORD        指定源镜像仓库密码, 非必填; 支持多个用 '|' 分隔，需要遵循 SOURCE_REGISTRY_URLS 变量配置顺序
    ```

## 1.1 单镜像同步示例
- 完整地址同步到完整地址
    ```bash
    bash docker-image-pusher.sh \
      -s registry.example.com/team/app:1.0 \
      -t harbor.example.com/prod/app:1.0
    ```
- 完整地址同步到多个目标仓库
    ```bash
    export PRIVATE_REGISTRY_URLS="harbor-a.example.com|harbor-b.example.com"
    export PRIVATE_REGISTRY_USERNAME="user-a|user-b"
    export PRIVATE_REGISTRY_PASSWORD="pass-a|pass-b"

    bash docker-image-pusher.sh \
      -s registry.example.com/team/app:1.0 \
      -t prod/app:1.0
    ```

## 1.2 `images.ini` 示例
```ini
# 源镜像=目标镜像1,目标镜像2
docker.io/library/nginx:stable-alpine=harbor.example.com/base/nginx:stable-alpine
registry.example.com/team/app:1.0=prod/app:1.0,harbor-backup.example.com/prod/app:1.0
```

## 1.3 `images.ini` 多目标规则
- 一行表示一个源镜像
- 多个目标镜像使用英文逗号 `,` 分隔
- 每个目标镜像都支持两种写法：
    - 完整地址：`harbor.example.com/base/nginx:latest`
    - 仓库内路径：`base/nginx:latest`
- 当目标写成仓库内路径时，脚本会继续按 `PRIVATE_REGISTRY_URLS` 展开
- 所以一行配置既可以写多个完整目标，也可以写多个相对目标，或两者混用

## 1.4 源/目标仓库认证
- 目标仓库认证：
    - `PRIVATE_REGISTRY_URLS`
    - `PRIVATE_REGISTRY_USERNAME`
    - `PRIVATE_REGISTRY_PASSWORD`
- 源仓库认证：
    - `SOURCE_REGISTRY_URLS`
    - `SOURCE_REGISTRY_USERNAME`
    - `SOURCE_REGISTRY_PASSWORD`
- 这 3 个源认证变量均为非必填
- 若源镜像本身已经带完整仓库地址，脚本会优先从镜像地址中识别源仓库
- 若源镜像未带仓库地址，则默认按 Docker Hub 处理
- 若需要配置多个源仓库认证，可像目标仓库一样使用 `|` 分隔
- 若同时需要 Docker Hub 与其他私有源仓库认证，请在 `SOURCE_REGISTRY_URLS` 中显式写上 `docker.io`
- 如果目标镜像是完整地址，但没有出现在 `PRIVATE_REGISTRY_URLS` 中，脚本会跳过预登录，并在推送失败时提示你检查认证配置
- 默认开启即时清理：每推送完一个目标镜像后，立即删除本地目标 tag；当前源镜像的全部目标处理完成后，立即删除本地源镜像，以降低磁盘占用
- 批量模式下，单个镜像同步失败不会中断整个任务；脚本会继续处理后续镜像，并在最后输出成功/失败汇总

## 1.5 `.env` 模板示例
```env
# 日志级别
LOG_LEVEL=INFO

# 是否在每次推送后立即清理本地镜像
IMAGES_CLEAN_FLAG=1

# 目标仓库配置，多个仓库使用 | 分隔，顺序必须一一对应
PRIVATE_REGISTRY_URLS=registry.cn-chengdu.aliyuncs.com|ghcr.io
PRIVATE_REGISTRY_USERNAME=aliyun_user|0x5c0f
PRIVATE_REGISTRY_PASSWORD=aliyun_password|github_pat_classic

# 源仓库配置
# 1) 若不填写 SOURCE_REGISTRY_URLS，未带 registry 前缀的源镜像默认按 Docker Hub 处理
# 2) 若要配置多个源仓库，使用 | 分隔，并保证三组变量顺序一一对应
# 3) 若同时要配置 Docker Hub + 私有源仓库，请显式将 docker.io 写入 SOURCE_REGISTRY_URLS
SOURCE_REGISTRY_URLS=
SOURCE_REGISTRY_USERNAME=
SOURCE_REGISTRY_PASSWORD=
```

- `PRIVATE_REGISTRY_URLS`、`PRIVATE_REGISTRY_USERNAME`、`PRIVATE_REGISTRY_PASSWORD` 的顺序必须严格对应
- `SOURCE_REGISTRY_URLS`、`SOURCE_REGISTRY_USERNAME`、`SOURCE_REGISTRY_PASSWORD` 在多源场景下也必须严格对应
- 若同步到 `ghcr.io`，建议 `PRIVATE_REGISTRY_PASSWORD` 使用 GitHub Personal Access Token（classic）
- `.env` 仅用于本地或自建服务器运行；GitHub Actions 请改为配置 `Secrets` / `Variables`

## 2. 使用`Github Actions` 自动同步  
- 在项目 `Settings` -> `Secret and variables` -> `Actions` -> `New Repository secret`中，添加以下参数:  
    - `PRIVATE_REGISTRY_URLS`: 指定私有镜像仓库地址, 多个地址用 '|' 分隔. (注: 需通过`secrets`指定)  
    - `PRIVATE_REGISTRY_USERNAME`: 指定私有镜像仓库的登陆用户名, 多个用 '|' 分割，需要遵循 `PRIVATE_REGISTRY_URLS` 变量配置顺序 (注: 需通过`secrets`指定)    
    - `PRIVATE_REGISTRY_PASSWORD`: 指定私有镜像仓库的登陆密码, 多个用 '|' 分割，需要遵循 `PRIVATE_REGISTRY_URLS` 变量配置顺序 (注: 需通过`secrets`指定)    
    - 若源镜像拉取也需要认证，可增加:
        - `SOURCE_REGISTRY_URLS`
        - `SOURCE_REGISTRY_USERNAME`
        - `SOURCE_REGISTRY_PASSWORD`
    - 其他变量: `LOG_LEVEL` 指定日志级别. (注: 通过 `variables`指定)
- 修改 `images.ini` 配置文件，然后提交到`Github`， `Github Actions` 将会自动执行同步  
- 当前工作流会自动：
    - 在 `Step Summary` 中输出同步结果汇总
    - 上传完整日志为 `docker-image-pusher-log` artifact
    - 当存在失败镜像时，任务最后返回失败状态，便于告警和重试

## 2.1 同步到 `ghcr.io`
- 若需同步到 `ghcr.io`，请在 `PRIVATE_REGISTRY_URLS` 中追加 `ghcr.io`
- `PRIVATE_REGISTRY_USERNAME` 中对应填写 GitHub 用户名，例如 `0x5c0f`
- `PRIVATE_REGISTRY_PASSWORD` 中对应填写 GitHub Personal Access Token（classic），建议至少包含：
    - `write:packages`
    - `read:packages`
- `images.ini` 中建议直接写完整目标地址，例如：
```ini
alpine:latest=registry.cn-chengdu.aliyuncs.com/0x5c0f/alpine:latest,ghcr.io/0x5c0f/alpine:latest
```
- `ghcr.io/0x5c0f/alpine` 这类包第一次推送后默认通常是私有，需要在 GitHub Packages 页面手动改为公开；同一个包后续继续推送新 tag，一般不需要重复改可见性

# 已知问题
- 云厂商镜像仓库通常要求显式命名空间，建议在 `images.ini` 中直接写完整目标镜像地址

# 常见问题
- 报错 `denied: requested access to the resource is denied`
    - 检查目标仓库命名空间是否存在
    - 检查 `PRIVATE_REGISTRY_USERNAME` / `PRIVATE_REGISTRY_PASSWORD` 是否正确
    - 检查目标镜像所属仓库地址是否已出现在 `PRIVATE_REGISTRY_URLS`
- 推送前没有自动登录目标仓库
    - 如果目标镜像写的是完整地址，但对应仓库没出现在 `PRIVATE_REGISTRY_URLS`，脚本只会尝试直接推送，不会预登录
- 从私有源仓库拉取失败
    - 请检查 `SOURCE_REGISTRY_URLS`、`SOURCE_REGISTRY_USERNAME`、`SOURCE_REGISTRY_PASSWORD`
    - 若源镜像未带 registry 前缀，则默认会按 Docker Hub 处理
- 批量任务中有单个镜像失败
    - 脚本会继续处理后续镜像
    - 结束时输出失败列表
    - 退出码仍为非 `0`，用于 CI 正确标记失败
