#! /bin/bash

cat >> /etc/bash_audit <<"EOF"
# 以EOF作为结束标志，将内容追加写入/etc/bash_audit文件

#to avoid sourcing this file more than once
if [ "${OSTYPE:0:7}" != "solaris" ]    # 如果该操作系统不是solaris类型
then
  #do not source this file twice; also do not source it if we are in forcecommand.sh, source it later from "-bash-li"
  #if we would source it from forcecommand.sh, the environment would be lost after the call of 'exec -l bash -li'
if [ "$AUDIT_INCLUDED" == "$$" ] || { [ -z "$SSH_ORIGINAL_COMMAND" ] && [ "$(cat /proc/$$/cmdline)" == 'bash-c"/etc/forcecommand.sh"' ]; }
then
  return
else
  declare -rx AUDIT_INCLUDED="$$"
fi
fi
#---------------------bash的提示符颜色等无关紧要的配置-----------------
#prompt & color
_backnone="\e[00m"
_backblack="\e[40m"
_backblue="\e[44m"
_frontred_b="\e[01;31m"
_frontgreen_b="\e[01;32m"
_frontgrey_b="\e[01;37m"
_frontgrey="\e[00;37m"
_frontblue_b="\e[01;34m"
#PS1="\[${_backblue}${_frontgrey_b}\]\u@\h:\[${_backblack}${_frontblue_b}\]\w\\$\[${_backnone}${_frontgrey_b}\] " #grey
PS1="\[${_backblue}${_frontgreen_b}\]\u@\h:\[${_backblack}${_frontblue_b}\]\w\\$\[${_backnone}${_frontgreen_b}\] " #green
#PS1="\[${_backblue}${_frontred_b}\]\u@\h:\[${_backblack}${_frontblue_b}\]\w\\$\[${_backnone}${_frontred_b}\] " #red
declare -rx PS1

#--------------------------------------------------------------------
#'history' options
# 在这部分对有关SHELL历史的设置进行一下调整

# 注： declare -rx 是声明只读环境变量

declare -rx HISTFILE="$HOME/.bash_history"
declare -rx HISTSIZE=500000                      #内存中的history条数，退出登陆之后会写到~/.bash_history文件里
#这里如果设置为0，那么SHELL则不会记录任何命令
declare -rx HISTFILESIZE=500000                  #文件中存储的最大history条数，文件：~/.bash_history
declare -rx HISTCONTROL=""
# HISTCONTROL 这个环境变量可以控制历史的记录方式 在这里设置为空，即不忽略空格开头的命令和重复的命令
declare -rx HISTIGNORE=""
# HISTGNORE 用于让HISTORY在存储时忽略某些指令,这里设置为空，即不忽略任何指令
declare -rx HISTCMD                                         #历史记录行号
#------------------以上是默认配置————————————————------------------------

if [ "${OSTYPE:0:7}" != "solaris" ]     #以下配置在solaris中不生效
then
if groups | grep -q root                #判断当前是否是root用户
then
  declare -x TMOUT=3600                 #为root对话设置系统空闲等待时间，超过该等待时间后断开连接
  chattr +a "$HISTFILE"                 #设置HISTORY文件为只可增加属性
fi
fi
#---------------------------------------------
# shopt 命令用于显示和设置SHELL中的行为选项，通过这些选项以增强SHELL的易用性
shopt -s histappend                     #由于bash的history文件默认是覆盖，如果存在多个终端，最后退出的会覆盖以前历史记录，改为追加形式
shopt -s cmdhist                        #将一个多行命令的所有行保存在同一个历史项中
shopt -s histverify
#如果设置,且readline正被使用,历史替换的结果不会立即传递给shell解释器.而是将结果行装入readline编辑缓冲区中,允许进一步修改

#------------------------------------------------------------------------
#下面的方法可以给历史加上时间戳，但在这里并不采用
#add timestamps in history - obsoleted with logger/syslog
#'http://www.thegeekstuff.com/2008/08/15-examples-to-master-linux-command-line-history/#more-130'
#declare -rx HISTTIMEFORMAT='%F %T '

#enable forward search ('ctrl-s')
#'http://ruslanspivak.com/2010/11/25/bash-history-incremental-search-forward/'
#------------------------------------------------------------------

if shopt -q login_shell && [ -t 0 ]
then
  stty -ixon               # 启用XON/XOFF 流控制
fi
#XON/XOFF 是一种流控制协议（通信速率匹配协议），
#用于数据传输速率大于等于1200b/s时进行速率匹配，方法是控制发送方的发速率以匹配双方的速率。


#--------------------------下面是bash的审计和追踪的配置----------------
#
#
# who -mu 显示当前登陆系统的用户  其中 awk '{print $1}' 打印第一个字段,以下同理
# 这些步骤来获取我们需要的审计信息，并设置相应的环境变量
declare -rx AUDIT_LOGINUSER="$(who -mu | awk '{print $1}')"  #设置登陆用户
declare -rx AUDIT_LOGINPID="$(who -mu | awk '{print $6}')"   #设置登陆PID
declare -rx AUDIT_USER="$USER"                               #这个用户随着我们执行su/sudo而改变，注意第一个登陆用户是不变的
declare -rx AUDIT_PID="$$"                                   #当前Shell进程ID。对于 Shell 脚本，就是这些脚本所在的进程ID。
declare -rx AUDIT_TTY="$(who -mu | awk '{print $2}')"        #当前tty号，也就是终端号
declare -rx AUDIT_SSH="$([ -n "$SSH_CONNECTION" ] && echo "$SSH_CONNECTION" | awk '{print $1":"$2"->"$3":"$4}')"
#AUDIT_SSH为打印出通过SSH登陆的远程主机的IP地址和端口号，以及本地主机的IP地址和端口号
declare -rx AUDIT_STR="[audit $AUDIT_LOGINUSER/$AUDIT_LOGINPID as $AUDIT_USER/$AUDIT_PID on $AUDIT_TTY/$AUDIT_SSH]"
declare -x AUDIT_LASTHISTLINE=""                            #避免记录同一行两次
declare -rx AUDIT_SYSLOG="1"                                #使用一个本地的syslogd
#
#
#
#the logging at each execution of command is performed with a trap DEBUG function
#and having set the required history options (HISTCONTROL, HISTIGNORE)
#and to disable the trap in functions, command substitutions or subshells.
#it turns out that this solution is simple and works well with piped commands, subshells, aborted commands with 'ctrl-c', etc..
set +o functrace
#禁用在函数，命令替换或子shell中继承的trap DEBUG，通常是默认设置
shopt -s extglob                                        #启用模式匹配
function AUDIT_DEBUG() {
  if [ -z "$AUDIT_LASTHISTLINE" ]                           #初始化 如果 $AUDIT_LASTHISTLINE 为空 则
  then
    local AUDIT_CMD="$(fc -l -1 -1)"                        #设置AUDIT_CMD为上一条指令
    AUDIT_LASTHISTLINE="${AUDIT_CMD%%+([^ 0-9])*}"          #将这条指令的行号存储在AUDIT_LASTHISTLINE中
  else
    AUDIT_LASTHISTLINE="$AUDIT_HISTLINE"                    #否则存储当前命令的行号
  fi
  local AUDIT_CMD="$(history 1)"                            #current history command
  AUDIT_HISTLINE="${AUDIT_CMD%%+([^ 0-9])*}"                #将其设置为当前行AUDIT_HISTLINE的行
  if [ "${AUDIT_HISTLINE:-0}" -ne "${AUDIT_LASTHISTLINE:-0}" ] || [ "${AUDIT_HISTLINE:-0}" -eq "1" ]
  #避免记录在'ctrl-c'，'empty + enter'或'ctrl-d'之后未执行的命令
  then
    echo -ne "${_backnone}${_frontgrey}"                    #为命令的输出去除提示符的颜色
    #remove in last history cmd its line number (if any) and send to syslog
    if [ -n "$AUDIT_SYSLOG" ]                               #如果AUDIT_SYSLOG的长度不等于0,即设置了AUDIT_SYSLOG
    then
      #注：logger是一个shell命令接口，可以通过该接口使用Syslog的系统日志模块，还可以从命令行直接向系统日志文件写入一行信息
      #  logger -p 优先级  -t 指定标记   日志信息
      if ! logger -p user.info -t "$AUDIT_STR $PWD" "${AUDIT_CMD##*( )?(+([0-9])?(\*)+( ))}"
      then       #进行异常处理
        echo error "$AUDIT_STR $PWD" "${AUDIT_CMD##*( )?(+([0-9])?(\*)+( ))}"
      fi
    else    #如果AUDIT_SYSLOG未设置, 把日志输出到我们指定的文件/var/log/userlog.info
      echo $( date +%F_%H:%M:%S ) "$AUDIT_STR $PWD" "${AUDIT_CMD##*( )?(+([0-9])?(\*)+( ))}" >>/var/log/userlog.info
    fi
    return 0
  else
    return 1
  fi
}
#
#
#
#-----------------------------会话结束时的审计函数----------------------------
function AUDIT_EXIT() {
  local AUDIT_STATUS="$?"        # $? 是显示最后命令的退出状态，0表示没有错误，其他表示有错误
  if [ -n "$AUDIT_SYSLOG" ]      # 如果AUDIT_SYSLOG的长度不等于0,即设置了AUDIT_SYSLOG
  then                           # 利用logger -p 命令 写入syslog
    logger -p user.info -t "$AUDIT_STR" "#=== session closed ==="
  else                           # 否则写入文件 /var/log/userlog.info
    echo $( date +%F_%H:%M:%S ) "$AUDIT_STR" "#=== session closed ===" >>/var/log/userlog.info
  fi
  exit "$AUDIT_STATUS"
}
#
#---------------------------------------------------------------------------
#声明审计陷入函数的属性为只读， 同时disable trap DEBUG继承
declare -frx +t AUDIT_DEBUG
declare -frx +t AUDIT_EXIT
#
#
#
#-------------------------会话开始时进行审计-----------------------------
if [ -n "$AUDIT_SYSLOG" ] # 如果AUDIT_SYSLOG的长度不等于0,即设置了AUDIT_SYSLOG
then                      # 利用logger -p 命令 写入syslog
  logger -p user.info -t "$AUDIT_STR" "#=== session opened ==="
else                       # 否则写入文件 /var/log/userlog.info
  echo $( date +%F_%H:%M:%S ) "$AUDIT_STR" "#=== session opened ===" >>/var/log/userlog.info
fi
#
#
#
#当一个BASH命令被执行的时候，他首先会出发我们预设好的AUDIT_DEBUG()函数
#然后trap DEBUG被disable掉，防止一些流水线命令执行的时候产生一些不必要审计信息
#最后，当提示符重新出现时，我们重新enable trap DEBUG

declare -rx PROMPT_COMMAND="[ -n \"\$AUDIT_DONE\" ] && echo '-----------------------------'; AUDIT_DONE=; trap 'AUDIT_DEBUG && AUDIT_DONE=1; trap DEBUG' DEBUG"
declare -rx BASH_COMMAND                                    #定义环境变量：当前被用户执行的命令
declare -rx SHELLOPT                                        #定义SHELLOPT选项
trap AUDIT_EXIT EXIT                                        #会话结束时进行审计
#注：trap command signal   表示接收到EXIT信号的时候执行 AUDIT_EXIT 动作

#endof
EOF


chown root:root /etc/bash_audit     #改变/etc/bash_audit的所有者
chmod 644 /etc/bash_audit           #改变/etc/bash_audit的权限为644 rw-r--r--

#/etc/profile /etc/skel/.bashrc /root/.bashrc /home/*/.bashrc 均是BASH的配置文件
#/etc/profile 这个文件是为系统的每个用户设置环境信息（当每个用户第一次登录时,该文件被执行）
#~/.bashrc 这个文件是每个用户专用于自己的bash shell的bash信息（当登录时以及每次打开新的shell时,该文件被读取）
#下面的命令一次把/etc/bash_audit写入这些配置文件中

for i in /etc/profile /etc/skel/.bashrc /root/.bashrc /home/*/.bashrc; do
  if ! grep -q ". /etc/bash_audit" "$i"
  then
    echo "===updating $i==="
    echo "[ -f /etc/bash_audit ] && . /etc/bash_audit #added by franzi" >>"$i"
    # [ -f /etc/bash_audit ] 判断这个文件是否存在
  fi
done

#在/etc/rsyslog.conf中追加下列信息
cat >>/etc/rsyslog.conf <<"EOF"

$ActionFileDefaultTemplate RSYSLOG_FileFormat
#stop avahi if messages are dropped (cf. /var/log/messages with 'net_ratelimit' or 'imuxsock begins to drop')
#update-rc.d -f avahi-daemon remove && service avahi-daemon stop
#$SystemLogRateLimitInterval 10
#$SystemLogRateLimitBurst 500
$SystemLogRateLimitInterval 0
#endof
EOF

#在/etc/rsyslog.d/45-xsserver.conf追加下列信息
cat >/etc/rsyslog.d/45-xsserver.conf <<"EOF"
#added by franzi

# Filter duplicated messages
$RepeatedMsgReduction off

# Enable high precision timestamps
$ActionFileDefaultTemplate RSYSLOG_FileFormat

# Log bash audit generated log messages to file
if $syslogfacility-text == 'user' and $syslogseverity-text == 'info' and $syslogtag startswith '[audit' then /var/log/userlog.info

#then drop them
& ~

EOF

/etc/init.d/rsyslog restart
