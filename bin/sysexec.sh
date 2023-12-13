#!/usr/bin/ksh
#
# Execute commands on remote host
#

# Source common library file
BASE_DIR=/usr/scripts
SYS_LIB=${BASE_DIR}/lib/_sys.lib
if [[ ! -f ${SYS_LIB} ]]; then
    # If we can't source _sys.lib we can't do anything
    echo "$0: ${SYS_LIB} not found" >&2 && exit 1
fi
. ${SYS_LIB}

# Source reqired library files
eval $(sys_source_lib fs)

################
# Functions
################

# Show usage help
function prog_usage
{
    echo "Usage: ${PROG_NAME} [-c conffile] [-u user] [-o "ssh_options"]"
    echo "          [-h \"host ...\"] [-l \"listfile ...\"]"
    echo "          { [-e command] [-f \"cmdfile ...\"] | command }"
    exit 1
}

# Get command line arguments
function prog_getopts
{
    typeset _opt
    typeset _host _list
    typeset _cmds
    typeset _f
    typeset -i _enum=0
    typeset -i _fnum=0

    while getopts :c:e:f:h:l:o:u: _opt
    do
	case ${_opt} in
	    c)
		CONF_FILE="${OPTARG}"
		fs_is_abspath ${CONF_FILE} || CONF_FILE=${SYS_PWD}/${CONF_FILE}
		;;
	    e)
		# Collect -e and -f options in order they appear
		# and save arguments in the set of variables (like arrays)
		let "_enum += 1"
		[[ -z "${_cmds}" ]] && _cmds="E${_enum}" || _cmds="${_cmds} E${_enum}"
		eval _SE_CMD_E${_enum}=\"\${OPTARG}\"
		;;
	    f)
		# Collect -e and -f options in order they appear
		# and save arguments in the set of variables (like arrays)
		for _f in ${OPTARG}
		do
		    let "_fnum += 1"
		    [[ -z "${_cmds}" ]] && _cmds="F${_fnum}" || _cmds="${_cmds} F${_fnum}"
		    eval _SE_CMD_F${_fnum}=\"\${_f}\"
		done
		;;
	    h)
		# Collect values if the same option is used multiple times
		[[ -z "${_host}" ]] && _host="${OPTARG}" || _host="${_host} ${OPTARG}"
		;;
	    l)
		# Collect values if the same option is used multiple times
		[[ -z "${_list}" ]] && _list="${OPTARG}" || _list="${_list} ${OPTARG}"
		;;
	    o)
		sys_setoptvar SYSEXEC_SSHOPTS="${OPTARG}"
		;;
	    u)
		sys_setoptvar SYSEXEC_USER="${OPTARG}"
		;;
	    :)
		sys_err_msg "argument missing for option '${OPTARG}'"
		prog_usage
		;;
	    ?)
		sys_err_msg "wrong option '${OPTARG}'"
		prog_usage
		;;
	esac
    done
    shift $((${OPTIND} - 1))
    [[ $# -gt 0 ]] && _SE_CMDARG="$@"

    # Set variable with the order of -e and -f options
    [[ -n "${_cmds}" ]] && _SE_CMDS="${_cmds}"
    # Set collected option values
    [[ -n "${_host}" ]] && sys_setoptvar SYSEXEC_HOST="${_host}"
    [[ -n "${_list}" ]] && sys_setoptvar SYSEXEC_LIST="${_list}"
}

################
# Main
################

# Uncomment the next line for functions debug
#for i in $(typeset +f); do typeset -ft $i; done

# Default configuration file in ${CONF_DIR} directory
CONF_FILE=${CONF_DIR}/sysexec.conf

# Default values for configuration variables
sys_setdefvar SYSEXEC_USER="${SYS_USER}"
sys_setdefvar SYSEXEC_HOST=""
sys_setdefvar SYSEXEC_LIST=""
sys_setdefvar SYSEXEC_CMD=""
sys_setdefvar SYSEXEC_CMDFILE=""
sys_setdefvar SYSEXEC_SSHOPTS="-o ConnectTimeout=10"

# Some internal variables:
# _SE_CMDARG is used if <command> is set via command line
_SE_CMDARG=""
# _SE_CMDS is used to keep ordered list of -e and -f options
_SE_CMDS=""

# Get command line arguments
prog_getopts "$@"

# Read configuration file
sys_read_conf ${CONF_FILE}

# Set variables (from default, config, environment and options)
sys_setvars

#
# Well, we've got all to do the work. :)
#

# Temporary files names
_TMP_FILE=${TMP_DIR}/${PROG_NAME}.$$.${RANDOM}
TMP_CMDFILE=${_TMP_FILE}.cmd
TMP_HOSTLIST=${_TMP_FILE}.lst

# Check if user is set
if [[ -z "${SYSEXEC_USER}" ]]; then
    sys_err_msg "<user> is not set"
    prog_usage
fi

# If SYSEXEC_HOST and SYSEXEC_LIST are empty
# then we should not do anything
if [[ -z "${SYSEXEC_HOST}" && -z "${SYSEXEC_LIST}" ]]; then
    sys_err_msg "neither <host> nor <hostlist> is set"
    prog_usage
fi

if [[ -n "${_SE_CMDARG}" || -n "${_SE_CMDS}" ]]; then
    # If <command> is set as argument (_SE_CMDARG is set)
    # or if several -e and -f options are used (_SE_CMDS is set)
    # then ignore SYSEXEC_CMD and SYSEXEC_CMDFILE
    # which may be set via configuration file or environment
    SYSEXEC_CMD=""
    SYSEXEC_CMDFILE=""
else
    # Otherwise if SYSEXEC_CMD and SYSEXEC_CMDFILE are empty
    # then we should not do anything
    if [[ -z "${SYSEXEC_CMD}" && -z "${SYSEXEC_CMDFILE}" ]]; then
	sys_err_msg "neither <command> nor <cmdfile> is set"
	prog_usage
    fi
fi

# Empty temporary files, exit if the files can't be created
: >${TMP_CMDFILE}
[[ $? -ne 0 ]] && sys_err_exit "can't create file ${TMP_CMDFILE}"
: >${TMP_HOSTLIST}
[[ $? -ne 0 ]] && sys_err_exit "can't create file ${TMP_HOSTLIST}"

# Remove temporary files and exit if the script is trapped
trap "rm -f ${TMP_CMDFILE} ${TMP_HOSTLIST}; exit 130" 1 2 15

# Form the list of commands in the TMP_CMDFILE file:
if [[ -n "${_SE_CMDARG}" ]]; then
    # If <command> is set as argument (_SE_CMDARG is set)
    # then just put it in the list of commands
    echo "${_SE_CMDARG}" >>${TMP_CMDFILE}
elif [[ -n "${_SE_CMDS}" ]]; then
    # If several -e and -f options are used (_SE_CMDS is set)
    # then process that options in order
    for _opt in ${_SE_CMDS}
    do
	eval _f=\"\${_SE_CMD_${_opt}}\"
	[[ -z "${_f}" ]] && continue
	if [[ "${_opt}" = E* ]]; then
	    # If this is -e option (command argument)
	    # then just put it in the list of commands
	    echo "${_f}" >>${TMP_CMDFILE}
	elif [[ "${_opt}" = F* ]]; then
	    # If this is -f option (file argument)
	    # then copy the contents of this file to the list of commands
	    [[ -f ${_f} && -r ${_f} ]] && cat ${_f} >>${TMP_CMDFILE} || \
		sys_warn_msg "${_f} not found or not readable"
	fi
    done
else
    # First SYSEXEC_CMD is processed and then SYSEXEC_CMDFILE
    if [[ -n "${SYSEXEC_CMD}" ]]; then
	# Just put it in the list of commands
	echo "${SYSEXEC_CMD}" >>${TMP_CMDFILE}
    fi
    if [[ -n "${SYSEXEC_CMDFILE}" ]]; then
	# SYSEXEC_CMDFILE may be set as the list of files
	for _f in ${SYSEXEC_CMDFILE}
	do
	    # If the path is not absolute
	    # then check path relative to CONF_DIR directory
	    fs_is_abspath ${_f} || _f=${CONF_DIR}/${_f}
	    [[ -f ${_f} && -r ${_f} ]] && cat ${_f} >>${TMP_CMDFILE} || \
		sys_warn_msg "${_f} not found or not readable"
	done
    fi
fi

# If the resulting list of commands is not empty
# then form the list of hosts in the TMP_HOSTLIST file:
if [[ -s ${TMP_CMDFILE} ]]; then
    # First SYSEXEC_HOST is processed and then SYSEXEC_LIST
    if [[ -n "${SYSEXEC_HOST}" ]]; then
	for _h in ${SYSEXEC_HOST}
	do
	    # Just put the host in the list of hosts
	    echo "${_h}" >>${TMP_HOSTLIST}
	done
    fi
    if [[ -n "${SYSEXEC_LIST}" ]]; then
	for _f in ${SYSEXEC_LIST}
	do
	    # If the path is not absolute
	    # first check path relative to current working directory
	    # then check path relative to CONF_DIR directory
	    fs_is_abspath ${_f} || {
		[[ -f ${SYS_PWD}/${_f} ]] && _f=${SYS_PWD}/${_f} || \
		    _f=${CONF_DIR}/${_f}
	    }
	    fs_read_listfile "${_f}" >>${TMP_HOSTLIST}
	done
    fi

    # If the resulting list of hosts is not empty
    # then execute the list of commands in TMP_CMDFILE
    # on the list of hosts in TMP_HOSTLIST
    if [[ -s ${TMP_HOSTLIST} ]]; then
	while read _h
	do
	    cat ${TMP_CMDFILE} | ssh ${SYSEXEC_SSHOPTS} -T -l ${SYSEXEC_USER} ${_h}
	done <${TMP_HOSTLIST}
    fi
fi

# Delete temporary file
rm -f ${TMP_CMDFILE} ${TMP_HOSTLIST}
