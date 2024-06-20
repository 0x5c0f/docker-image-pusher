# push docker images 
使用`Github Actions`推送`Docker`官方仓库镜像到其他仓库 

# 使用方法
## 1. 自建服务器部署
- 克隆仓库到可以直接拉取镜像的服务器上面，然后根据脚本帮助配置运行即可 
- 详细配置查看脚本帮助说明
    ```ini
    Usage: docker-image-pusher.sh [-h] [-c] [-s] [-t] [-e environment]

    Options:
    -h, --help                          展示帮助文档并退出.
    -c images_file                      指定同步的配置文件, 默认 /home/cxd/Projects/tmpdir/docker-image-pusher/images.ini.
    -s source_tag                       单镜像同步时，指定同步的源镜像
    -t target_tag                       单镜像同步时，指定同步的目标镜像
    -e environment                      指定环境变量, 用以覆盖内置变量(key=value,key=value)

    Image_file:
        配置文件格式: 
            源镜像=目标镜像
        配置文件示例:
            nginx=base/nginx
            docker.io/nginx=hub.example.com/base/nginx
    Source_tag:
        源镜像, 支持所有不登陆就可以拉取的镜像
            - nginx
            - docker.io/nginx
    Target_tag:
        目标镜像
            - base/nginx
            - hub.example.com/base/nginx
            - '-hub.example.com/base/nginx' (指定仓库同步)
    Environment:
        所有支持的参数，均可以通过系统环境变量进行传递。(优先级: 参数指定 > -e 指定 > 系统环境变量 > 配置文件指定)
    系统变量:
        LOG_LEVEL                       日志级别, 默认 INFO(INFO/WARN/DEBUG/ERROR)
        IMAGES_FILE                     指定同步的配置文件, 默认 /home/cxd/Projects/tmpdir/docker-image-pusher/images.ini
        HUB_IMAGE_TAG                   指定同步的源镜像
        NEW_IMAGE_TAG                   指定同步的目标镜像(需要设置: PRIVATE_REGISTRY_URLS)
        PRIVATE_REGISTRY_URLS           指定私有镜像仓库地址, 多个地址用逗号分隔, 默认 ''
        PRIVATE_REGISTRY_USERNAME       指定私有镜像仓库的登陆用户名, 多个用逗号分割，需要遵循 PRIVATE_REGISTRY_URLS 变量配置顺序
        PRIVATE_REGISTRY_PASSWORD       指定私有镜像仓库的登陆密码, 多个用逗号分割，需要遵循 PRIVATE_REGISTRY_URLS 变量配置顺序
        DOCKER_USERNAME                 指定 DockerHub 登陆用户名, 非必填, 默认 ''
        DOCKER_PASSWORD                 指定 DockerHub 登陆密码, 非必填, 默认 ''
    ```

## 2. 使用`Github Actions` 自动同步  
- 在项目 `Settings` -> `Secret and variables` -> `Actions` -> `New Repository secret`中，添加以下参数:  
    - `PRIVATE_REGISTRY_URLS`: 指定私有镜像仓库地址, 多个地址用逗号分隔. (注: 需通过`secrets`指定)  
    - `PRIVATE_REGISTRY_USERNAME`: 指定私有镜像仓库的登陆用户名, 多个用逗号分割，需要遵循 `PRIVATE_REGISTRY_URLS` 变量配置顺序 (注: 需通过`secrets`指定)    
    - `PRIVATE_REGISTRY_PASSWORD`: 指定私有镜像仓库的登陆密码, 多个用逗号分割，需要遵循 `PRIVATE_REGISTRY_URLS` 变量配置顺序 (注: 需通过`secrets`指定)    
    - 其他变量: `LOG_LEVEL` 指定日志级别. (注: 通过 `variables`指定)
- 修改 `images.ini` 配置文件，然后提交到`Github`， `Github Actions` 将会自动执行同步  
