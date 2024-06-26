#!/usr/bin/bash
################################################# 
#   author      0x5c0f 
#   date        2024-06-19 
#   email       mail@0x5c0f.cc 
#   web         tools.0x5c0f.cc 
#   version     1.1.0
#   last update 2024-06-19
#   descript    Use : ./docker-image-pusher.sh -h
################################################# 

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

# base script dir 
# BASEDIR=$(cd $(dirname $0); pwd)
BASEDIR=$(dirname $(readlink -f "$0"))

LOG_LEVEL="${LOG_LEVEL:-INFO}"

HUB_IMAGE_TAG="${HUB_IMAGE_TAG:-}"
NEW_IMAGE_TAG="${NEW_IMAGE_TAG:-}"

IMAGES_FILE="${BASEDIR}/images.ini"

DOCKER_USERNAME="${DOCKER_USERNAME:-}"
DOCKER_PASSWORD="${DOCKER_PASSWORD:-}"

PRIVATE_REGISTRY_URLS="${PRIVATE_REGISTRY_URLS:-}"
PRIVATE_REGISTRY_USERNAME="${PRIVATE_REGISTRY_USERNAME:-}"
PRIVATE_REGISTRY_PASSWORD="${PRIVATE_REGISTRY_PASSWORD:-}"


CLOUD_REGISTRY_DOMAINS="aliyuncs.com|tencentyun.com|myhuaweicloud.com"

## __SAY__ [info|success|error|warn|debug] <message>
## __SAY__ [info|success|error|warn|debug] bg <message>
__SAY__() {
    local -r ENDCOLOR="\033[0m"
    local -r INFOCOLOR="\033[1;34m"    # info color
    local -r SUCCESSCOLOR="\033[0;32m" # success color
    local -r ERRORCOLOR="\033[0;31m"   # error color
    local -r WARNCOLOR="\033[0;33m"    # warning color
    local -r DEBUGCOLOR="\033[0;35m"   # debug color
    
    # 判断下传入的第一个参数是不是数字，防止提取变量时候出错
    expr "${1:0:1}" "+" 0 >/dev/null 2>&1 && {
        LOGTYPE="INFOCOLOR"
    } || {

        if [ "${LOG_LEVEL^^}" == "INFO" ]; then
            if [ "${1^^}" == "DEBUG" -o "${1^^}" == "ERROR" -o "${1^^}" == "WARN" ]; then
                return 0
            fi
        elif [ "${LOG_LEVEL^^}" == "WARN" ]; then
            if [ "${1^^}" == "DEBUG" -o "${1^^}" == "ERROR" ]; then
                return 0
            fi
        elif [ "${LOG_LEVEL^^}" == "ERROR" ]; then
            if [ "${1^^}" == "DEBUG" ]; then
                return 0
            fi
        elif [ "${LOG_LEVEL^^}" == "DEBUG" ]; then
            true
        else
            if [ "${1^^}" == "DEBUG" -o "${1^^}" == "ERROR" -o "${1^^}" == "WARN" ]; then
                return 0
            fi
        fi

        LOGTYPE="${1^^}COLOR"
        if [ "${!LOGTYPE}x" == "x" ]; then
            # 未获取到已经配置的颜色标记，设置为默认颜色
            LOGTYPE="INFOCOLOR"
        else
            shift
        fi
    }

    MESSAGE="$@"
    if [ "${1}" == "bg" ]; then
        shift
        MESSAGE="${!LOGTYPE}$@${ENDCOLOR}"
    fi

    echo -e "[$(date '+%Y-%m-%d_%H:%M:%S')] [${!LOGTYPE}${LOGTYPE%%COLOR}${ENDCOLOR}] ${MESSAGE}"
}

_DOCKERHUB_LOGIN() {
    if [ "${DOCKER_USERNAME}x" != "x" -a "${DOCKER_PASSWORD}x" != "x" ]; then
        __SAY__ info "开始登陆: DockerHub"
        docker login -u "${DOCKER_USERNAME}" -p "${DOCKER_PASSWORD}"
    fi
}

_REGISTRY_LOGIN(){
    # PRIVATE_REGISTRY_URLS 是必需配置的
    if [ "${PRIVATE_REGISTRY_URLS}x" != "x" ]; then
        IFS='|' read -ra PRIVATE_REGISTRY_URLS_ARR <<<"${PRIVATE_REGISTRY_URLS}"
        IFS='|' read -ra PRIVATE_REGISTRY_USERNAME_ARR <<<"${PRIVATE_REGISTRY_USERNAME}"
        IFS='|' read -ra PRIVATE_REGISTRY_PASSWORD_ARR <<<"${PRIVATE_REGISTRY_PASSWORD}"
        for ((i=0; i<${#PRIVATE_REGISTRY_URLS_ARR[@]}; i++)); do
            __PRIVATE_REGISTRY_URL__="${PRIVATE_REGISTRY_URLS_ARR[$i]}"
            __PRIVATE_REGISTRY_USERNAME__="${PRIVATE_REGISTRY_USERNAME_ARR[$i]}"
            __PRIVATE_REGISTRY_PASSWORD__="${PRIVATE_REGISTRY_PASSWORD_ARR[$i]}"
            __SAY__ info "开始登陆: ${__PRIVATE_REGISTRY_URL__}" 
            docker login -u "${__PRIVATE_REGISTRY_USERNAME__}" -p "${__PRIVATE_REGISTRY_PASSWORD__}" "${__PRIVATE_REGISTRY_URL__}"
        done
    else
        __SAY__ error "未配置私有镜像仓库地址，请检查 !!!"
        exit $LINENO
    fi
}

_IMAGE_SYNC_TO_REGISTRY_CHECK() {
    local -- _HUB_IMAGE_TAG="${HUB_IMAGE_TAG:-${1}}"
    local -- _NEW_IMAGE_TAG="${NEW_IMAGE_TAG:-${2}}"

    local -i __FLAG__=0
    # TODO: 这儿应该程序自动判定的，我搞不出来，只能让 images.ini 传入的时候固定了
    if echo "${_NEW_IMAGE_TAG}" | grep -qE '^-' ; then
        __SAY__ debug "检查到同步目标为指定仓库地址同步, 更正标识 ${_NEW_IMAGE_TAG} 为 ${_NEW_IMAGE_TAG#-}"
        _NEW_IMAGE_TAG="${_NEW_IMAGE_TAG#-}"
        __FLAG__=1
    fi

    # fix: 把 http(s):// 头给删除
    local -- __HUB_IMAGE_TAG__="${_HUB_IMAGE_TAG#*://}"
    local -- __NEW_IMAGE_TAG__="${_NEW_IMAGE_TAG#*://}"

    __SAY__ debug "镜像同步配置状态: ${__HUB_IMAGE_TAG__} -> ${__NEW_IMAGE_TAG__}"

    __SAY__ info "pull 待同步镜像: ${__HUB_IMAGE_TAG__}"

    docker pull ${__HUB_IMAGE_TAG__} || {
        __SAY__ error "镜像拉取失败，跳过同步 ${__HUB_IMAGE_TAG__}"
        return 0
    }

    if [ "${__FLAG__}" == "1" ]; then
        # 指定域名同步
        __SAY__ info "镜像同步: ${__HUB_IMAGE_TAG__} -> ${__NEW_IMAGE_TAG__}"
        docker tag ${__HUB_IMAGE_TAG__} ${__NEW_IMAGE_TAG__}
        docker push ${__NEW_IMAGE_TAG__} || {
            __SAY__ error "镜像同步失败 ${__NEW_IMAGE_TAG__}"
            return 0
        }
    else
        # 镜像同步
        if [ "${PRIVATE_REGISTRY_URLS}x" != "x" ]; then
            IFS='|' read -ra PRIVATE_REGISTRY_URLS_ARR <<<"${PRIVATE_REGISTRY_URLS}"
            for __PRIVATE_REGISTRY_URL__ in ${PRIVATE_REGISTRY_URLS_ARR[@]}; do
                ___NEW_IMAGE_TAG___="${__PRIVATE_REGISTRY_URL__#*://}/${__NEW_IMAGE_TAG__}"

                if echo "${__PRIVATE_REGISTRY_URL__}" | grep -Eq "${CLOUD_REGISTRY_DOMAINS}" ; then 
                    __SAY__ warn "多仓库同步状态下，不支持同步到云仓库固定命名空间, 跳过 ${___NEW_IMAGE_TAG___}"
                    continue 
                fi
                
                __SAY__ debug "镜像同步: ${__HUB_IMAGE_TAG__} -> ${___NEW_IMAGE_TAG___}"
                
                docker tag ${__HUB_IMAGE_TAG__} ${___NEW_IMAGE_TAG___}
                docker push ${___NEW_IMAGE_TAG___} || {
                    __SAY__ error "镜像同步失败 ${___NEW_IMAGE_TAG___}"
                    return 0
                }
            done
        else
            __SAY__ error "未配置私有镜像仓库地址，请检查 !!!"
            exit $LINENO
        fi
    fi

}

__PCHECK__(){
    _DOCKERHUB_LOGIN
    _REGISTRY_LOGIN
}

main(){
    # 判断配置文件是否存在
    if [ ! -f "${IMAGES_FILE}" ]; then
        __SAY__ error "${IMAGES_FILE} not exist"
        exit $LINENO
    else
        __SAY__ info "开始读取同步镜像信息"
        __IMAGES_LINE__=$(grep -v '^\s*$' ${IMAGES_FILE} | grep -v '^\s*#' | tr '\n' ' ')
        for __IMAGES_LINE__ in ${__IMAGES_LINE__}; do
            IFS='=' read -ra __IMAGES_ARR__ <<<"${__IMAGES_LINE__}"
            __HUB_IMAGE_TAG__="${__IMAGES_ARR__[0]}"
            __NEW_IMAGE_TAG__="${__IMAGES_ARR__[1]}"
            _IMAGE_SYNC_TO_REGISTRY_CHECK "${__HUB_IMAGE_TAG__}" "${__NEW_IMAGE_TAG__}"
        done
    fi
}

__HELP__() {
    echo "Usage: $(basename $0) [-h] [-c] [-s] [-t] [-e environment]"
    echo ""
    echo "Options:"
    echo "  -h, --help                          展示帮助文档并退出."
    echo "  -c images_file                      指定同步的配置文件, 默认 ${IMAGES_FILE}."
    echo "  -s source_tag                       单镜像同步时，指定同步的源镜像"
    echo "  -t target_tag                       单镜像同步时，指定同步的目标镜像"
    echo "  -e environment                      指定环境变量, 用以覆盖内置变量(key=value,key=value)"
    echo ""
    echo "Image_file:"
    echo "      配置文件格式: "
    echo "          源镜像=目标镜像"
    echo "      配置文件示例:" 
    echo "          nginx=base/nginx"
    echo "          docker.io/nginx=-hub.example.com/base/nginx"
    echo "Source_tag:"
    echo "      源镜像, 支持所有不登陆就可以拉取的镜像"
    echo "          - nginx"
    echo "          - docker.io/nginx"
    echo "Target_tag:"
    echo "      目标镜像"
    echo "          - base/nginx"
    echo "          - '-hub.example.com/base/nginx' (指定仓库同步)"
    echo "Environment:"
    echo "      所有支持的参数，均可以通过系统环境变量进行传递。(优先级: 参数指定 > -e 指定 > 系统环境变量 > 配置文件指定)"
    echo "系统变量:"
    echo "      LOG_LEVEL                       日志级别, 默认 ${LOG_LEVEL}(INFO/WARN/DEBUG/ERROR)"
    echo "      IMAGES_FILE                     指定同步的配置文件, 默认 ${IMAGES_FILE}"
    echo "      HUB_IMAGE_TAG                   指定同步的源镜像"
    echo "      NEW_IMAGE_TAG                   指定同步的目标镜像(需要设置: PRIVATE_REGISTRY_URLS)"
    echo "      PRIVATE_REGISTRY_URLS           指定私有镜像仓库地址, 多个地址用 '|' 分隔, 默认 ${PRIVATE_REGISTRY_URLS:-''}"
    echo "      PRIVATE_REGISTRY_USERNAME       指定私有镜像仓库的登陆用户名, 多个用 '|' 分割，需要遵循 PRIVATE_REGISTRY_URLS 变量配置顺序"
    echo "      PRIVATE_REGISTRY_PASSWORD       指定私有镜像仓库的登陆密码, 多个用 '|' 分割，需要遵循 PRIVATE_REGISTRY_URLS 变量配置顺序"
    echo "      DOCKER_USERNAME                 指定 DockerHub 登陆用户名, 非必填, 默认 ${DOCKER_USERNAME:-''}"
    echo "      DOCKER_PASSWORD                 指定 DockerHub 登陆密码, 非必填, 默认 ${DOCKER_PASSWORD:-''}"
}

while getopts "hc:s:t:e:" opt; do
    case $opt in
    h)
        __HELP__
        exit 0
        ;;
    c)
        IMAGES_FILE=$OPTARG
        ;;
    s)
        HUB_IMAGE_TAG=$OPTARG
        ;;
    t)
        NEW_IMAGE_TAG=$OPTARG
        ;;
    e)
        ENV_VARS=$OPTARG
        ;;
    :)
        echo "Option -$OPTARG requires an argument." >&2
        __HELP__
        exit 1
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        # __HELP__
        exit 1
        ;;
    esac
done

shift $((OPTIND - 1))

IFS=',' read -ra ENV_ARR <<<"$ENV_VARS"
for var in "${ENV_ARR[@]}"; do
    IFS='=' read -ra VAR_ARR <<<"$var"
    declare -g "${VAR_ARR[0]}=${VAR_ARR[1]}"
done

if [ -f "${BASEDIR}/.env" ]; then
    __SAY__ info "检查到环境变量配置文件(${BASEDIR}/.env),开始加载..."
    source ${BASEDIR}/.env
fi

# PRIVATE_REGISTRY_URLS=""
# PRIVATE_REGISTRY_USERNAME=""
# PRIVATE_REGISTRY_PASSWORD=""
# LOG_LEVEL=DEBUG

__PCHECK__

if [ "${HUB_IMAGE_TAG}x" == "x" -o  "${NEW_IMAGE_TAG}x" == "x"  ]; then
    main
else
    _IMAGE_SYNC_TO_REGISTRY_CHECK ${HUB_IMAGE_TAG} ${NEW_IMAGE_TAG}
fi
